from __future__ import annotations
from typing import List
from django.utils import timezone
from django.db import transaction
from celery import shared_task

from onchannels.models import ScheduledNotification
from user_sessions.models import Device
from common.fcm_sender import send_to_token, send_to_topic


@shared_task(bind=True, autoretry_for=(Exception,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def enqueue_notification(self, notification_id: int) -> bool:
    # Idempotency guard: lock the row and only send if still pending
    with transaction.atomic():
        n = ScheduledNotification.objects.select_for_update(skip_locked=True).filter(id=notification_id).first()
        if not n:
            return False
        if n.status != ScheduledNotification.STATUS_PENDING:
            return False
        # proceed to dispatch while holding the lock
        result = _dispatch_single(n)
    return result


def _dispatch_single(n: ScheduledNotification) -> bool:
    try:
        # Optional delivery hints
        ttl = None
        collapse = None
        try:
            if isinstance(n.data, dict):
                ttl = n.data.get('_ttl')
                collapse = n.data.get('_collapse') or n.data.get('_collapse_key')
                if isinstance(ttl, str) and ttl.isdigit():
                    ttl = int(ttl)
        except Exception:
            ttl = None
            collapse = None

        if n.target_type == ScheduledNotification.TARGET_TOKEN:
            if not n.target_value:
                raise ValueError("Missing target_value for token notification")
            send_to_token(n.title, n.body, n.target_value, (n.data or {}), ttl_seconds=ttl, collapse_key=collapse)
            _mark_sent(n)
            return True
        elif n.target_type == ScheduledNotification.TARGET_TOPIC:
            if not n.target_value:
                raise ValueError("Missing target_value (topic)")
            send_to_topic(n.title, n.body, n.target_value, (n.data or {}), ttl_seconds=ttl, collapse_key=collapse)
            _mark_sent(n)
            return True
        elif n.target_type == ScheduledNotification.TARGET_USER:
            if not n.target_user_id:
                raise ValueError("Missing target_user for user notification")
            devices: List[Device] = list(Device.objects.filter(user_id=n.target_user_id, push_enabled=True).exclude(push_token="").all())
            if not devices:
                raise ValueError("No devices with push_token for target user")
            for d in devices:
                if not d.push_token:
                    continue
                try:
                    send_to_token(n.title, n.body, d.push_token, (n.data or {}), ttl_seconds=ttl, collapse_key=collapse)
                except Exception as exc:
                    # Log but continue with other devices
                    _set_error(n, f"Device {d.id}: {exc}")
            _mark_sent(n)
            return True
        else:
            raise ValueError(f"Unknown target_type: {n.target_type}")
    except Exception as exc:
        _record_failure(n, str(exc))
        raise


def _mark_sent(n: ScheduledNotification) -> None:
    n.status = ScheduledNotification.STATUS_SENT
    n.attempts = (n.attempts or 0) + 1
    n.last_error = ""
    n.save(update_fields=["status", "attempts", "last_error", "updated_at"])


def _record_failure(n: ScheduledNotification, error: str) -> None:
    n.status = ScheduledNotification.STATUS_FAILED
    n.attempts = (n.attempts or 0) + 1
    n.last_error = (error or "")[:1000]
    n.save(update_fields=["status", "attempts", "last_error", "updated_at"])


@shared_task(bind=True)
def dispatch_due_notifications(self) -> int:
    now = timezone.now()
    due = list(ScheduledNotification.objects.select_for_update(skip_locked=True).filter(status=ScheduledNotification.STATUS_PENDING, send_at__lte=now)[:50])
    count = 0
    if not due:
        return 0
    with transaction.atomic():
        for n in due:
            # Re-fetch locked row in transaction to avoid double-send
            n = ScheduledNotification.objects.select_for_update().get(pk=n.pk)
            if not n.is_due():
                continue
            try:
                _dispatch_single(n)
                count += 1
            except Exception:
                # failure recorded inside _dispatch_single
                continue
    return count
