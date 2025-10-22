import os
import time
from datetime import timedelta
from typing import Optional, Dict, List, Tuple

import firebase_admin
from firebase_admin import credentials, messaging
from django.db import transaction
from django.utils import timezone
import logging
try:
    from onchannels.models import UserNotification
except Exception:  # pragma: no cover
    UserNotification = None  # type: ignore
try:
    from user_sessions.models import Device
except Exception:  # pragma: no cover
    Device = None  # type: ignore

_initialized = False
logger = logging.getLogger(__name__)


def _ensure_initialized() -> None:
    global _initialized
    if _initialized:
        return
    # Initialize with GOOGLE_APPLICATION_CREDENTIALS if present
    creds_path = os.environ.get("FIREBASE_CREDENTIALS_JSON") or os.environ.get("GOOGLE_APPLICATION_CREDENTIALS")
    if creds_path and os.path.exists(creds_path):
        logger.info("[FCM] Initializing Firebase Admin with credentials at %s", creds_path)
        try:
            cred = credentials.Certificate(creds_path)
            firebase_admin.initialize_app(cred)
            logger.info("[FCM] Firebase Admin initialized successfully")
        except Exception as e:  # noqa: BLE001
            logger.exception("[FCM] Firebase Admin initialization failed: %s", e)
            raise
    else:
        # Fallback to default creds (useful on GCP)
        try:
            logger.info("[FCM] Initializing Firebase Admin with default credentials (no explicit JSON path)")
            firebase_admin.initialize_app()
            logger.info("[FCM] Firebase Admin initialized successfully (default)")
        except Exception:
            raise RuntimeError(
                "Firebase Admin failed to initialize. Set FIREBASE_CREDENTIALS_JSON or GOOGLE_APPLICATION_CREDENTIALS to service account JSON.")
    _initialized = True


def send_to_token(
    title: str,
    body: str,
    token: str,
    data: Optional[Dict[str, str]] = None,
    ttl_seconds: Optional[int] = None,
    collapse_key: Optional[str] = None,
) -> str:
    """Send a notification to a single FCM registration token."""
    _ensure_initialized()
    notification = messaging.Notification(title=title, body=body)

    android_config = None
    if ttl_seconds or collapse_key:
        android_config = messaging.AndroidConfig(
            ttl=timedelta(seconds=int(ttl_seconds)) if ttl_seconds else None,
            collapse_key=collapse_key,
        )

    apns_config = None
    if ttl_seconds or collapse_key:
        headers = {}
        if ttl_seconds:
            headers["apns-expiration"] = str(int(time.time()) + int(ttl_seconds))
        if collapse_key:
            headers["apns-collapse-id"] = collapse_key
        apns_config = messaging.APNSConfig(headers=headers)

    message = messaging.Message(
        notification=notification,
        data={k: str(v) for k, v in (data or {}).items()},
        token=token,
        android=android_config,
        apns=apns_config,
    )
    try:
        logger.debug("[FCM] Sending to token (len=%d) title='%s' collapse_key='%s' ttl=%s",
                     len(token or ""), title, collapse_key, ttl_seconds)
        resp = messaging.send(message, dry_run=False)
        logger.info("[FCM] Send success: %s", resp)
        return resp
    except Exception as e:  # noqa: BLE001
        logger.exception("[FCM] Send failed for token prefix=%s...: %s", (token or "")[:12], e)
        raise


def _is_invalid_token_error(exc: Exception) -> bool:
    """Heuristic to detect invalid/expired FCM tokens from Firebase errors."""
    text = str(exc).lower()
    needles = [
        'registration-token-not-registered',
        'not registered',
        'invalidregistration',
        'mismatchsenderid',
        'invalid argument',
    ]
    return any(n in text for n in needles)


def send_to_user(
    user_id: int,
    title: str,
    body: str,
    data: Optional[Dict[str, str]] = None,
    ttl_seconds: Optional[int] = None,
    collapse_key: Optional[str] = None,
) -> Tuple[List[str], List[str]]:
    """Send a notification to all active devices of a user.

    Returns (success_tokens, failed_tokens). Invalid tokens are automatically
    disabled (push_enabled=False) in the Device table.
    """
    if Device is None:
        raise RuntimeError('Device model not available')

    tokens: List[str] = list(
        Device.objects.filter(user_id=user_id, push_enabled=True)
        .exclude(push_token__isnull=True)
        .exclude(push_token='')
        .values_list('push_token', flat=True)
    )
    logger.info("[FCM] user_id=%s has %d push-enabled device token(s)", user_id, len(tokens))
    if not tokens:
        return ([], [])

    ok: List[str] = []
    bad: List[str] = []

    for tok in tokens:
        try:
            send_to_token(
                title=title,
                body=body,
                token=tok,
                data=data,
                ttl_seconds=ttl_seconds,
                collapse_key=collapse_key,
            )
            ok.append(tok)
            logger.debug("[FCM] user_id=%s token prefix=%s...: sent OK", user_id, (tok or "")[:12])
        except Exception as exc:  # noqa: BLE001
            bad.append(tok)
            logger.warning("[FCM] user_id=%s token prefix=%s...: send FAILED: %s", user_id, (tok or "")[:12], exc)
            if _is_invalid_token_error(exc):
                try:
                    with transaction.atomic():
                        Device.objects.filter(push_token=tok).update(push_enabled=False)
                    logger.info("[FCM] Disabled invalid token for user_id=%s token prefix=%s...", user_id, (tok or "")[:12])
                except Exception:
                    logger.exception("[FCM] Failed to disable invalid token for user_id=%s token prefix=%s...", user_id, (tok or "")[:12])
            continue

    # Persist a UserNotification if model is available and at least one token was targeted
    if UserNotification is not None and (ok or tokens):
        try:
            # Determine tenant context if needed; default to 'ontime'
            tenant = 'ontime'
            UserNotification.objects.create(
                user_id=user_id,
                tenant=tenant,
                title=title,
                body=body or '',
                data={k: str(v) for k, v in (data or {}).items()} or None,
                created_at=timezone.now(),
            )
            logger.debug("[FCM] UserNotification persisted for user_id=%s (ok=%d, targeted=%d)", user_id, len(ok), len(tokens))
        except Exception:
            logger.exception("[FCM] Failed to persist UserNotification for user_id=%s", user_id)

    return (ok, bad)


def send_to_topic(
    title: str,
    body: str,
    topic: str,
    data: Optional[Dict[str, str]] = None,
    ttl_seconds: Optional[int] = None,
    collapse_key: Optional[str] = None,
) -> str:
    """Send a notification to all devices subscribed to a topic."""
    _ensure_initialized()
    notification = messaging.Notification(title=title, body=body)

    android_config = None
    if ttl_seconds or collapse_key:
        android_config = messaging.AndroidConfig(
            ttl=timedelta(seconds=int(ttl_seconds)) if ttl_seconds else None,
            collapse_key=collapse_key,
        )

    apns_config = None
    if ttl_seconds or collapse_key:
        headers = {}
        if ttl_seconds:
            headers["apns-expiration"] = str(int(time.time()) + int(ttl_seconds))
        if collapse_key:
            headers["apns-collapse-id"] = collapse_key
        apns_config = messaging.APNSConfig(headers=headers)

    message = messaging.Message(
        notification=notification,
        data={k: str(v) for k, v in (data or {}).items()},
        topic=topic,
        android=android_config,
        apns=apns_config,
    )
    resp = messaging.send(message, dry_run=False)
    return resp
