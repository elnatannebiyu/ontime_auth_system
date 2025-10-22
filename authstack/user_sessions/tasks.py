from __future__ import annotations
from typing import Optional, Dict

from celery import shared_task

from common.fcm_sender import send_to_token, send_to_topic


@shared_task(bind=True, autoretry_for=(Exception,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def send_push_to_token(self, title: str, body: str, token: str, data: Optional[Dict[str, str]] = None) -> bool:
    send_to_token(title, body, token, data or {})
    return True


@shared_task(bind=True, autoretry_for=(Exception,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def send_push_to_topic(self, title: str, body: str, topic: str, data: Optional[Dict[str, str]] = None) -> bool:
    send_to_topic(title, body, topic, data or {})
    return True
