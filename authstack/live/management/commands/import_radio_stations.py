import json
import sys
from typing import Any
from urllib.parse import urlencode, quote
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError

from django.core.management.base import BaseCommand, CommandError
from django.utils.text import slugify
from django.conf import settings

from ...models import LiveRadio

API_ROOT = "https://api.radio-browser.info/json"
UA = "ontime/1.0 (admin@ontime)"
PREFERRED_MIRRORS = [
    "https://de1.api.radio-browser.info/json",
    "https://de2.api.radio-browser.info/json",
    "https://at1.api.radio-browser.info/json",
    "https://nl1.api.radio-browser.info/json",
]


def get_servers(force_base: str | None = None) -> list[str]:
    # Returns a list of full base URLs like https://de1.api.radio-browser.info/json
    if force_base:
        return [force_base]
    servers_url = f"{API_ROOT}/servers"
    req = Request(servers_url, headers={"User-Agent": UA})
    try:
        with urlopen(req, timeout=8) as resp:
            arr = json.loads(resp.read().decode("utf-8"))
            out: list[str] = []
            for s in arr:
                name = s.get("name") or s.get("ip")
                if not name:
                    continue
                base = f"https://{name}/json"
                out.append(base)
            # Always include anycast root as last fallback
            all_servers = PREFERRED_MIRRORS + out + [API_ROOT]
            # de-dup while preserving order
            seen = set()
            unique = []
            for u in all_servers:
                if u not in seen:
                    seen.add(u)
                    unique.append(u)
            return unique
    except Exception:
        # Fall back to preferred mirrors plus anycast
        return PREFERRED_MIRRORS + [API_ROOT]


def try_fetch(url: str) -> list[dict[str, Any]]:
    req = Request(url, headers={"User-Agent": UA})
    with urlopen(req, timeout=12) as resp:
        body = resp.read().decode("utf-8")
        data = json.loads(body)
        if not isinstance(data, list):
            raise ValueError("unexpected response format")
        return data


def fetch_radio_browser(params: dict[str, Any], *, verbose: bool = False, force_base: str | None = None) -> list[dict[str, Any]]:
    # Assemble candidate URLs across servers and endpoint variants
    limit = int(params.get("limit") or 200)
    hide = "true"
    country = params.get("country")
    name = params.get("name")
    language = params.get("language")
    tag = params.get("tag")
    # best-effort country code for some countries if not provided
    cc = params.get("countrycode")
    if not cc and country and str(country).lower() == "ethiopia":
        cc = "ET"

    servers = get_servers(force_base)
    candidates: list[str] = []

    for base in servers:
        if country:
            c = quote(str(country))
            # Preferred: stations/search with richer filters similar to mobile client
            q = {
                "country": str(country),
                "countrycode": cc or "",
                "order": "votes",
                "reverse": "true",
                "hidebroken": hide,
                "lastcheckok": "1",
                "limit": limit,
            }
            # remove empty countrycode to avoid filtering wrongly
            if not q["countrycode"]:
                q.pop("countrycode")
            candidates.append(f"{base}/stations/search?{urlencode(q)}")
            # Fallbacks
            if cc:
                candidates.append(f"{base}/stations/bycountrycodeexact/{quote(cc)}?limit={limit}&hidebroken={hide}")
            candidates.append(f"{base}/stations/bycountryexact/{c}?limit={limit}&hidebroken={hide}")
            candidates.append(f"{base}/stations/bycountry/{c}?limit={limit}&hidebroken={hide}")
            candidates.append(f"{base}/stations?country={quote(str(country))}&limit={limit}&hidebroken={hide}")
        if name or language or tag:
            q: dict[str, Any] = {}
            if name:
                q["name"] = name
            if language:
                q["language"] = language
            if tag:
                q["tag"] = tag
            q["limit"] = limit
            q["hidebroken"] = hide
            candidates.append(f"{base}/stations/search?{urlencode(q)}")
        if not country and not (name or language or tag):
            candidates.append(f"{base}/stations?limit={limit}&hidebroken={hide}")

    last_err: Exception | None = None
    for url in candidates:
        try:
            if verbose:
                print(f"[radio-import] Trying {url}")
            return try_fetch(url)
        except Exception as e:
            last_err = e
            continue
    raise CommandError(f"Upstream error: {last_err}")


class Command(BaseCommand):
    help = "Import/sync radio stations from radio-browser.info into LiveRadio (idempotent by stationuuid)."

    def add_arguments(self, parser):
        parser.add_argument("--tenant", type=str, default="ontime")
        parser.add_argument("--country", type=str, default=None)
        parser.add_argument("--language", type=str, default=None)
        parser.add_argument("--tag", type=str, default=None)
        parser.add_argument("--name", type=str, default=None, help="Search by name substring")
        parser.add_argument("--limit", type=int, default=200, help="Max rows to import")
        parser.add_argument("--mirror", type=str, default=None, help="Force a specific mirror base URL, e.g., https://de1.api.radio-browser.info/json")
        parser.add_argument("--verbose", action="store_true", help="Verbose logging")

    def handle(self, *args, **options):
        tenant = options["tenant"]
        params: dict[str, Any] = {}
        if options.get("name"):
            params["name"] = options["name"]
        if options.get("country"):
            params["country"] = options["country"]
        if options.get("language"):
            params["language"] = options["language"]
        if options.get("tag"):
            params["tag"] = options["tag"]
        # Let the API limit the number of items if possible
        if options.get("limit"):
            params["limit"] = int(options["limit"]) or 200

        self.stdout.write(self.style.NOTICE(f"Fetching radio-browser with params: {params}"))
        rows = fetch_radio_browser(params, verbose=bool(options.get("verbose")), force_base=options.get("mirror"))
        if not isinstance(rows, list):
            raise CommandError("Unexpected response format")

        limit = int(options["limit"])
        imported = 0
        updated = 0
        skipped = 0

        for row in rows:
            if imported + updated >= limit:
                break
            uuid = row.get("stationuuid")
            if not uuid:
                skipped += 1
                continue
            name = (row.get("name") or "").strip()
            if not name:
                skipped += 1
                continue
            url_resolved = row.get("url_resolved") or row.get("url") or ""
            if not url_resolved:
                skipped += 1
                continue

            # Build or find slug; avoid collisions by appending short uuid
            base_slug = slugify(f"{name}-{row.get('country') or ''}")[:90]
            slug = base_slug or slugify(uuid[:8])
            # ensure uniqueness on tenant
            if LiveRadio.objects.filter(tenant=tenant, slug=slug).exists():
                slug = f"{slug}-{uuid[:8]}"

            defaults = {
                "tenant": tenant,
                "description": row.get("homepage") or "",
                "language": (row.get("language") or "").split(",")[0],
                "country": row.get("country") or "",
                "city": row.get("state") or "",
                "category": (row.get("tags") or "").split(",")[0],
                "stream_url": url_resolved,
                "backup_stream_url": row.get("url") or "",
                "bitrate": int(row.get("bitrate") or 0) or None,
                "format": row.get("codec") or "",
                "is_active": bool(row.get("lastcheckok")),
                "is_verified": bool(row.get("lastcheckok")),
                "logo": row.get("favicon") or "",
                "website_url": row.get("homepage") or "",
                "listener_count": 0,
                "total_listens": 0,
                "priority": 100,
            }

            # Upsert by (tenant, slug) first; if exists by name, update
            obj, created = LiveRadio.objects.get_or_create(
                tenant=tenant,
                slug=slug,
                defaults={
                    "name": name,
                    **defaults,
                },
            )
            if created:
                imported += 1
            else:
                # Update minimal fields
                for k, v in defaults.items():
                    setattr(obj, k, v)
                obj.name = name
                updated += 1
                obj.save()

        self.stdout.write(self.style.SUCCESS(f"Imported: {imported}, Updated: {updated}, Skipped: {skipped}"))
