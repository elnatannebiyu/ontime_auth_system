from django.core.management.base import BaseCommand, CommandError
from typing import Optional, Dict
import json

from common.fcm_sender import send_to_user


class Command(BaseCommand):
    help = "Send a test push notification to all active devices of a user."

    def add_arguments(self, parser):
        parser.add_argument("--user-id", type=int, required=True, help="Target user id")
        parser.add_argument("--title", type=str, required=True, help="Notification title")
        parser.add_argument("--body", type=str, required=True, help="Notification body")
        parser.add_argument("--data", type=str, default="{}", help='Optional JSON data payload, e.g. "{\\"link\\": \\\"/inbox\\\"}"')
        parser.add_argument("--ttl", type=int, default=None, help="Optional TTL seconds")
        parser.add_argument("--collapse-key", type=str, default=None, help="Optional collapse key")

    def handle(self, *args, **options):
        user_id: int = options["user_id"]
        title: str = options["title"]
        body: str = options["body"]
        raw_data: str = options.get("data") or "{}"
        ttl: Optional[int] = options.get("ttl")
        collapse_key: Optional[str] = options.get("collapse_key")

        try:
            data: Dict[str, str] = json.loads(raw_data)
            data = {str(k): str(v) for k, v in data.items()}
        except Exception as exc:
            raise CommandError(f"Invalid JSON for --data: {exc}")

        self.stdout.write(self.style.WARNING(
            f"Sending push to user_id={user_id}: title='{title}', body='{body}', data={data}, ttl={ttl}, collapse_key={collapse_key}"
        ))

        ok, bad = send_to_user(
            user_id=user_id,
            title=title,
            body=body,
            data=data,
            ttl_seconds=ttl,
            collapse_key=collapse_key,
        )

        self.stdout.write(self.style.SUCCESS(f"Sent to {len(ok)} token(s)"))
        if bad:
            self.stdout.write(self.style.WARNING(f"Failed for {len(bad)} token(s): {bad}"))
