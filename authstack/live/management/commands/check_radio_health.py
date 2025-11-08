import time
from typing import Optional
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

from django.core.management.base import BaseCommand
from django.utils import timezone

from ...models import LiveRadio

UA = "ontime-radio-health/1.0"


def probe(url: str, timeout: float = 7.0) -> tuple[bool, str]:
    req = Request(url, headers={"User-Agent": UA})
    try:
        with urlopen(req, timeout=timeout) as resp:
            ct = resp.headers.get("Content-Type", "").lower()
            # Read a tiny chunk to confirm bytes flow (not always necessary for HLS)
            try:
                chunk = resp.read(1024)
            except Exception:
                chunk = b""
            # Consider ok if HTTP 200-ish and either audio, hls playlist, or any data
            status = getattr(resp, "status", 200)
            ok = (200 <= status < 300) and (
                "audio/" in ct or
                "application/vnd.apple.mpegurl" in ct or
                "application/x-mpegurl" in ct or
                len(chunk) > 0
            )
            if not ok:
                return False, f"bad_status_or_type status={status} ct={ct}"
            return True, "ok"
    except HTTPError as e:
        return False, f"http_error {e.code}"
    except URLError as e:
        return False, f"url_error {getattr(e, 'reason', e)}"
    except Exception as e:
        return False, f"error {e}"


class Command(BaseCommand):
    help = "Probe LiveRadio.stream_url, update last_check_ok/at/last_error and toggle is_active/is_verified on result."

    def add_arguments(self, parser):
        parser.add_argument("--tenant", type=str, default="ontime")
        parser.add_argument("--slug", type=str, default=None)
        parser.add_argument("--country", type=str, default=None)
        parser.add_argument("--only-inactive", action="store_true")
        parser.add_argument("--limit", type=int, default=100)
        parser.add_argument("--set-inactive-on-fail", action="store_true")
        parser.add_argument("--set-verified-on-pass", action="store_true")

    def handle(self, *args, **opts):
        tenant = opts["tenant"]
        slug = opts.get("slug")
        country = opts.get("country")
        only_inactive = bool(opts.get("only_inactive"))
        limit = int(opts.get("limit") or 100)
        set_inactive = bool(opts.get("set_inactive_on_fail"))
        set_verified = bool(opts.get("set_verified_on_pass"))

        qs = LiveRadio.objects.filter(tenant=tenant)
        if slug:
            qs = qs.filter(slug=slug)
        if country:
            qs = qs.filter(country__iexact=country)
        if only_inactive:
            qs = qs.filter(is_active=False)
        qs = qs.order_by("-updated_at")[:limit]

        checked = 0
        ok_count = 0
        fail_count = 0

        for r in qs:
            ok, reason = probe(r.stream_url)
            r.last_check_ok = ok
            r.last_check_at = timezone.now()
            r.last_error = "" if ok else reason[:250]
            if ok and set_verified:
                r.is_verified = True
                r.is_active = True
            if (not ok) and set_inactive:
                r.is_active = False
            r.save(update_fields=[
                "last_check_ok", "last_check_at", "last_error",
                "is_active", "is_verified", "updated_at"
            ])
            checked += 1
            if ok:
                ok_count += 1
                self.stdout.write(self.style.SUCCESS(f"OK  {r.slug} {r.stream_url}"))
            else:
                fail_count += 1
                self.stdout.write(self.style.WARNING(f"BAD {r.slug} {r.stream_url} -> {reason}"))

        self.stdout.write(self.style.NOTICE(
            f"Checked={checked} ok={ok_count} fail={fail_count}"
        ))
