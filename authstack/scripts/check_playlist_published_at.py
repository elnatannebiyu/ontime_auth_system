#!/usr/bin/env python3
import os
import sys
import argparse
import requests

DEFAULT_BASE = os.environ.get("ONTIME_API_BASE", "https://0.0.0.0:8000")
TENANT = os.environ.get("ONTIME_TENANT", "ontime")


def login(base, username, password, verify=True):
    url = f"{base}/api/token/"
    r = requests.post(
        url,
        json={"username": username, "password": password},
        headers={"X-Tenant-Id": TENANT},
        timeout=15,
        verify=verify,
    )
    r.raise_for_status()
    data = r.json()
    return data.get("access")


def get_playlist(base, access, playlist_id, verify=True):
    url = f"{base}/api/channels/playlists/"
    # Use search by id (DRF SearchFilter supports id in search_fields)
    params = {"search": playlist_id, "page_size": 1}
    r = requests.get(
        url,
        params=params,
        headers={"Authorization": f"Bearer {access}", "X-Tenant-Id": TENANT},
        timeout=15,
        verify=verify,
    )
    r.raise_for_status()
    data = r.json()
    results = data if isinstance(data, list) else data.get("results", [])
    if not results:
        return None
    # Pick exact id match if present
    for it in results:
        if it.get("id") == playlist_id:
            return it
    return results[0]


def main():
    p = argparse.ArgumentParser(description="Login and fetch playlist yt_published_at")
    p.add_argument("--base", default=DEFAULT_BASE, help="API base, default: %(default)s")
    p.add_argument("--user", default=os.environ.get("ONTIME_USER", "elu"))
    p.add_argument("--passw", dest="password", default=os.environ.get("ONTIME_PASS", "Root@1324"))
    p.add_argument("--playlist", default=os.environ.get("ONTIME_PLAYLIST", "PLM1o5wml9rzqcebiUTC9vI-Anx8SUb9lY"))
    p.add_argument("--insecure", action="store_true", help="Disable SSL verification (useful for local self-signed certs)")
    args = p.parse_args()

    base = args.base.rstrip("/")
    verify = not args.insecure
    if not verify:
        try:
            import urllib3  # noqa: WPS433
            urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)
        except Exception:
            pass

    print(f"Base: {base}\nTenant: {TENANT}\nUser: {args.user}\nInsecure SSL: {str(not verify).lower()}")

    try:
        access = login(base, args.user, args.password, verify=verify)
    except Exception as e:
        print(f"Login failed: {e}")
        sys.exit(1)

    try:
        pl = get_playlist(base, access, args.playlist, verify=verify)
    except Exception as e:
        print(f"Fetch failed: {e}")
        sys.exit(1)

    if not pl:
        print("Playlist not found")
        sys.exit(2)

    print("id:", pl.get("id"))
    print("title:", pl.get("title"))
    print("item_count:", pl.get("item_count"))
    print("yt_published_at:", pl.get("yt_published_at"))
    print("yt_last_item_published_at:", pl.get("yt_last_item_published_at"))


if __name__ == "__main__":
    main()
