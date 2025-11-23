from django.core.management.base import BaseCommand, CommandError
from django.utils import timezone
from typing import List, Set

from series.models import Season, Episode
from onchannels.youtube_api import YouTubeAPIError, get_playlist, list_playlist_items, get_video_privacy_status


EXCLUDE_DEFAULT = [
    "trailer",
    "teaser",
    "promo",
    "shorts",
    "clip",
]


class Command(BaseCommand):
    help = "Sync a Season from its mapped YouTube playlist using a minimal quota pattern."

    def add_arguments(self, parser):
        parser.add_argument("season", type=str, help="Season id (pk) or show_slug:number e.g. abbay-tv:2")
        parser.add_argument("--tenant", type=str, default=None, help="Tenant slug filter (optional)")
        parser.add_argument("--dry-run", action="store_true", help="Do not modify DB, just print changes")

    def handle(self, *args, **options):
        season_ref = options["season"]
        tenant = options.get("tenant")
        dry_run = options.get("dry_run", False)

        season = self._resolve_season(season_ref, tenant)
        if not season:
            raise CommandError("Season not found. Use pk or show_slug:number (e.g., abbay-tv:1)")

        if not season.is_enabled:
            self.stdout.write(self.style.WARNING("Season is disabled; proceeding with sync anyway (admin run)."))

        # Build rules
        include_rules = list(season.include_rules or [])
        exclude_rules = list(season.exclude_rules or [])
        if not exclude_rules:
            exclude_rules = EXCLUDE_DEFAULT

        # 1) Heartbeat: fetch playlist meta (cheap)
        try:
            meta = get_playlist(season.yt_playlist_id)
        except YouTubeAPIError as e:
            raise CommandError(f"Playlist heartbeat failed: {e}")

        item_count = int(meta.get("itemCount") or 0)
        self.stdout.write(f"Heartbeat: itemCount={item_count}")

        # Known videos set to detect new tail items and stop early
        known: Set[str] = set(
            Episode.objects.filter(season=season).values_list("source_video_id", flat=True)
        )

        created = 0
        updated = 0
        seen_new: List[str] = []

        # 2) Tail-only fetch: iterate from start but stop when we hit known tail
        # Simpler approach: iterate forward but short-circuit when we hit a fully known window.
        # For minimal calls, we could compute tail pages by difference, but forward with early stop is OK for most seasons.
        page_token = None
        try:
            while True:
                data = list_playlist_items(season.yt_playlist_id, page_token=page_token, max_results=50)
                items = data.get("items", [])
                if not items:
                    break
                for it in items:
                    vid = it.get("videoId")
                    title = (it.get("title") or "").strip()
                    if not vid:
                        continue
                    if vid in known:
                        # Already ingested; skip but continue scanning to pick up any newer items.
                        continue
                    # Apply exclusion keywords (case-insensitive)
                    t_low = title.lower()
                    if any(x in t_low for x in exclude_rules):
                        continue
                    # Optionally include-only rules (simple contains match)
                    if include_rules:
                        if not any(x.lower() in t_low for x in include_rules):
                            continue
                    seen_new.append(vid)

                    if dry_run:
                        continue

                    # Upsert Episode with minimal fields; episode_number assignment rule can be improved later
                    # Note: we do not override visibility/status for existing episodes here to respect
                    # any manual changes made in the admin.
                    ep, was_created = Episode.objects.update_or_create(
                        season=season,
                        source_video_id=vid,
                        defaults={
                            "tenant": season.tenant,
                            "title": title,
                            "thumbnails": it.get("thumbnails") or {},
                            "source_published_at": self._parse_published(it.get("publishedAt")),
                            "status": Episode.STATUS_PUBLISHED,
                        },
                    )

                    if was_created:
                        # Decide initial visibility based on YouTube privacyStatus.
                        try:
                            privacy_status = get_video_privacy_status(vid)
                        except YouTubeAPIError:
                            privacy_status = None

                        if privacy_status == "private":
                            ep.visible = False
                        else:
                            # Public/unlisted/unknown -> visible by default
                            ep.visible = True
                        ep.save(update_fields=["visible"])
                    if was_created:
                        created += 1
                    else:
                        updated += 1
                if not page_token:
                    break
                page_token = data.get("nextPageToken")
                if not page_token:
                    break
        except YouTubeAPIError as e:
            raise CommandError(f"Playlist items fetch failed: {e}")

        # 3) Update season last_synced_at
        if not dry_run:
            season.last_synced_at = timezone.now()
            season.save(update_fields=["last_synced_at", "updated_at"])

        self.stdout.write(self.style.SUCCESS(
            f"Sync complete: created={created}, updated={updated}, new_ids={len(seen_new)}"
        ))

    def _resolve_season(self, ref: str, tenant: str | None) -> Season | None:
        qs = Season.objects.all()
        if tenant:
            qs = qs.filter(tenant=tenant)
        if ref.isdigit():
            return qs.filter(pk=int(ref)).first()
        # show_slug:number format
        if ":" in ref:
            slug, num_str = ref.split(":", 1)
            try:
                num = int(num_str)
            except ValueError:
                return None
            return qs.select_related("show").filter(show__slug=slug, number=num).first()
        return None

    def _parse_published(self, s: str | None):
        if not s:
            return None
        # YouTube returns 2020-01-01T12:34:56Z
        try:
            from datetime import datetime, timezone as _tz
            return datetime.strptime(s, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=_tz.utc)
        except Exception:
            return None
