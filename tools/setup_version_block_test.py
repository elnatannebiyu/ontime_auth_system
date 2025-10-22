#!/usr/bin/env python3
"""
Quick setup/revert script for AppVersion block tests.

- Applies a forced update scenario for both iOS and Android:
  - Ensures 1.0.0 exists and is BLOCKED.
  - Ensures 1.0.1 exists and is ACTIVE with min_supported_version=1.0.1 and update_type=FORCED.
- Revert restores 1.0.0 to ACTIVE OPTIONAL and clears min_supported_version on 1.0.1.

Usage:
  # Apply block scenario (DB-only)
  python tools/setup_version_block_test.py --apply

  # Revert to permissive scenario (DB-only)
  python tools/setup_version_block_test.py --revert

  # Run HTTP tests against a running server (no DB mutation)
  python tools/setup_version_block_test.py --test \
    --base http://localhost:8000 --tenant ontime \
    --email "elu@gmail.com" --password "Root@1324" \
    --app-platform ios --app-version 1.0.0

Environment:
  DJANGO_SETTINGS_MODULE can be set; defaults to authstack.settings.
"""
from __future__ import annotations
import os
import sys
from typing import Tuple
import argparse
import json
import urllib.request
import urllib.error

# Ensure project root is importable when running from tools/
PROJECT_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
AUTHSTACK_ROOT = os.path.join(PROJECT_ROOT, "authstack")
for p in (PROJECT_ROOT, AUTHSTACK_ROOT):
    if p not in sys.path:
        sys.path.insert(0, p)

# Prepare Django (settings module: authstack/settings.py inside the inner package)
os.environ.setdefault("DJANGO_SETTINGS_MODULE", "authstack.settings")
import django  # type: ignore

django.setup()

from onchannels.version_models import AppVersion, VersionStatus, UpdateType  # type: ignore
from django.utils import timezone  # type: ignore


PLATFORMS = ("ios", "android")
CURR_VER = "1.0.0"
NEXT_VER = "1.0.1"


def ensure_version(platform: str, version: str, **defaults) -> Tuple[AppVersion, bool]:
    obj, created = AppVersion.objects.get_or_create(
        platform=platform,
        version=version,
        defaults={
            "build_number": 1,
            "version_code": 1,
            "status": VersionStatus.ACTIVE.value,
            "update_type": UpdateType.OPTIONAL.value,
            "released_at": timezone.now(),
            **defaults,
        },
    )
    # Update fields if existing
    changed = False
    for k, v in defaults.items():
        if getattr(obj, k) != v:
            setattr(obj, k, v)
            changed = True
    if changed:
        obj.save()
    return obj, created or changed


def apply_block_scenario() -> None:
    print("Applying forced update scenario for ios and android...")
    changes = 0
    for platform in PLATFORMS:
        # Current version 1.0.0 is BLOCKED
        _, ch1 = ensure_version(
            platform,
            CURR_VER,
            build_number=1,
            version_code=1,
            status=VersionStatus.BLOCKED.value,
            update_type=UpdateType.FORCED.value,
            force_update_message="This version is no longer supported. Please update to continue.",
        )
        changes += int(ch1)
        # Latest version 1.0.1 is ACTIVE and enforces min_supported_version
        _, ch2 = ensure_version(
            platform,
            NEXT_VER,
            build_number=2,
            version_code=2,
            status=VersionStatus.ACTIVE.value,
            update_type=UpdateType.FORCED.value,
            min_supported_version=NEXT_VER,
            update_message="A new version is available.",
            force_update_message="Please update to continue.",
        )
        changes += int(ch2)
    print(f"Done. Changes applied: {changes}")


def revert_block_scenario() -> None:
    print("Reverting to permissive scenario...")
    changes = 0
    for platform in PLATFORMS:
        try:
            cur = AppVersion.objects.get(platform=platform, version=CURR_VER)
            cur.status = VersionStatus.ACTIVE.value
            cur.update_type = UpdateType.OPTIONAL.value
            cur.save(update_fields=["status", "update_type", "updated_at"])
            changes += 1
        except AppVersion.DoesNotExist:
            pass
        try:
            nxt = AppVersion.objects.get(platform=platform, version=NEXT_VER)
            # Keep ACTIVE but clear strict enforcement
            if nxt.min_supported_version:
                nxt.min_supported_version = ""
                nxt.update_type = UpdateType.OPTIONAL.value
                nxt.save(update_fields=["min_supported_version", "update_type", "updated_at"])
                changes += 1
        except AppVersion.DoesNotExist:
            pass
    print(f"Done. Changes applied: {changes}")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description="Setup/revert AppVersion block scenarios and/or run HTTP tests.")
    parser.add_argument("--apply", action="store_true", help="Apply DB block scenario for ios/android")
    parser.add_argument("--revert", action="store_true", help="Revert DB to permissive scenario")
    parser.add_argument("--test", action="store_true", help="Run HTTP tests against a running server")
    parser.add_argument("--base", default=os.environ.get("BASE", "http://localhost:8000"), help="API base URL")
    parser.add_argument("--tenant", default=os.environ.get("TENANT", "ontime"), help="Tenant header value")
    parser.add_argument("--email", default=os.environ.get("TEST_EMAIL", ""), help="Login email for test")
    parser.add_argument("--password", default=os.environ.get("TEST_PASSWORD", ""), help="Login password for test")
    parser.add_argument("--app-platform", dest="app_platform", default="ios", choices=["ios", "android", "web"], help="Simulated app platform header")
    parser.add_argument("--app-version", dest="app_version", default="1.0.0", help="Simulated app version header")
    args = parser.parse_args(argv)

    rc = 0
    if args.apply:
        apply_block_scenario()
    if args.revert:
        revert_block_scenario()
    if args.test:
        rc |= run_http_tests(args)
    if not (args.apply or args.revert or args.test):
        parser.print_help()
        return 2
    return rc


def _http_request(url: str, method: str = "GET", headers: dict | None = None, data: dict | None = None):
    payload = None
    if data is not None:
        payload = json.dumps(data).encode("utf-8")
    req = urllib.request.Request(url, data=payload, method=method)
    for k, v in (headers or {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode("utf-8")
            return resp.status, body
    except urllib.error.HTTPError as e:
        try:
            body = e.read().decode("utf-8")
        except Exception:
            body = ""
        return e.code, body
    except Exception as e:
        return -1, str(e)


def run_http_tests(args) -> int:
    base = args.base.rstrip("/")
    tenant = args.tenant
    print(f"Testing against {base} (tenant={tenant}) as {args.email or '<no-email-provided>'}")

    # 1) Login (should be allowed even when blocks are applied)
    headers = {
        "X-Tenant-Id": tenant,
        "Content-Type": "application/json",
    }
    status, body = _http_request(
        f"{base}/api/token/",
        method="POST",
        headers=headers,
        data={"username": args.email, "password": args.password},
    )
    print(f"Login status={status}")
    try:
        parsed = json.loads(body) if body else {}
    except Exception:
        parsed = {"raw": body}
    access = parsed.get("access")
    if not access:
        print("Login failed or no access token returned; body:", parsed)
        return 1

    # 2) Call protected endpoint with simulated old app headers
    prot_headers = {
        "X-Tenant-Id": tenant,
        "Authorization": f"Bearer {access}",
        "X-Device-Platform": args.app_platform,
        "X-App-Version": args.app_version,
    }
    status2, body2 = _http_request(f"{base}/api/me/", headers=prot_headers)
    print(f"/api/me/ status={status2}")
    try:
        parsed2 = json.loads(body2) if body2 else {}
    except Exception:
        parsed2 = {"raw": body2}
    print(json.dumps(parsed2, indent=2))
    # Expect 426 when blocks are applied for version < min_supported or blocked status
    return 0 if status2 in (200, 401, 403, 426) else 2


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
