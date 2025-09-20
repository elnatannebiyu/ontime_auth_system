# Series: Add a Show from a Channel and Add a Second Season

This guide shows two quick ways (Admin UI and CLI) to:
- Create a Show linked to a Channel
- Add Season 1 (mapped to a YouTube playlist)
- Add Season 2 (a second playlist)
- Sync seasons and verify via API

Prerequisites
- Backend running at `http://localhost:8000`
- Tenant: `ontime`
- Channel (e.g., `EBS`) already exists with active playlists
- Admin access to Django

---

## Admin UI (Recommended)

1) Create the Show
- Go to: `Admin → Series → Shows → Add`
- Fields:
  - `Tenant`: `ontime`
  - `Channel`: select the source channel (e.g., EBS)
  - `Title`: suggestions appear from the channel’s active playlists; choose or type a custom title
  - `Slug`: leave blank to auto-generate (or set explicitly)
  - `Cover` (optional):
    - Upload via `cover_upload` to store a file under `/media/series/covers/shows/`
    - Or leave blank (the API will fall back to a Season cover later)
  - `Is active`: checked
- Save

2) Create Season 1
- Go to: `Admin → Series → Seasons → Add`
- Fields:
  - `Tenant`: `ontime`
  - `Show`: choose the Show created above
  - `Number`: `1`
  - `Yt playlist id`: after choosing Show, the dropdown auto-lists active playlists for the Show’s channel; pick Season 1 playlist
  - `Cover image` (optional): leave blank to auto-fill from playlist thumbnails; or upload via `cover_upload`
  - `Is enabled`: checked
  - `Sync now` (optional): check to ingest episodes immediately after save
- Save

3) Create Season 2 (Second Season)
- Go to: `Admin → Series → Seasons → Add`
- Fields:
  - `Tenant`: `ontime`
  - `Show`: same Show as above
  - `Number`: `2`
  - `Cover image` (optional): leave blank to auto-fill or upload via `cover_upload`
  - `Is enabled`: checked
  - `Sync now` (optional)
- Save

4) Verify Episodes
- Go to: `Admin → Series → Episodes`
- You should see episodes per season. Ordering defaults to your manual `episode_number` (nulls last), then `source_published_at`, then `id`.

Notes
- If `Season.cover_image` is blank and a playlist is selected, it auto-fills from YouTube thumbnails on save.
- If `Show.cover_image` is blank, the API falls back to the latest enabled Season’s `cover_image`.
- API returns absolute URLs for covers (e.g., `http://localhost:8000/media/...`).

---

## CLI (One-Liners)

Create a Show from a Channel (example: EBS → Ambassador):
```bash
python authstack/manage.py shell -c "
from onchannels.models import Channel; from series.models import Show;
ch = Channel.objects.get(id_slug='ebs');
show, created = Show.objects.get_or_create(
    tenant=ch.tenant,
    channel=ch,
    slug='ambassador',  # set your preferred slug
    defaults={'title': 'Ambassador', 'is_active': True}
)
print({'show': show.slug, 'created': created})
"
```

Create Season 1 (map to playlist):
```bash
python authstack/manage.py shell -c "
from series.models import Show, Season;
show = Show.objects.get(slug='ambassador');
season, created = Season.objects.get_or_create(
    tenant=show.tenant, show=show, number=1,
    defaults={'yt_playlist_id': 'PL_SEASON1_PLAYLIST', 'is_enabled': True}
)
print({'season_id': season.id, 'created': created})
"
```

Create Season 2 (second season):
```bash
python authstack/manage.py shell -c "
from series.models import Show, Season;
show = Show.objects.get(slug='ambassador');
season, created = Season.objects.get_or_create(
    tenant=show.tenant, show=show, number=2,
    defaults={'yt_playlist_id': 'PL_SEASON2_PLAYLIST', 'is_enabled': True}
)
print({'season_id': season.id, 'created': created})
"
```

Sync Seasons to ingest episodes:
```bash
python authstack/manage.py sync_season ambassador:1 --tenant=ontime
python authstack/manage.py sync_season ambassador:2 --tenant=ontime
```

---

## API Verification

All requests require:
- `Authorization: Bearer <access>`
- `X-Tenant-Id: ontime`

Endpoints:
- Shows: `GET /api/series/shows/`
- Seasons for a show: `GET /api/series/seasons/?show=<show_slug>`
- Episodes for a season: `GET /api/series/episodes/?season=<season_id>`
- Episode play: `GET /api/series/episodes/{episode_id}/play/`

Expected:
- Show `cover_image` is absolute URL; falls back to latest enabled season cover if empty
- Season `cover_image` is absolute URL (auto-filled from playlist if blank and playlist selected)
- Episodes are ordered by your manual `episode_number` (nulls last), then `source_published_at`, then `id`

---

## Troubleshooting

- Broken cover image (404):
  - Ensure the uploaded file exists under `MEDIA_ROOT` and you uploaded via `cover_upload`, or leave blank and rely on playlist thumbnail auto-fill.
  - Confirm Django dev is serving media (DEBUG=True; `urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)`).

- No playlists in Season form:
  - Mark playlists active via `Admin → Onchannels → Playlists` (filter by Channel).
  - After selecting `Show`, the playlist dropdown auto-populates.

- Episodes not in expected order:
  - Set `episode_number` manually; default ordering prioritizes `episode_number` ascending (nulls last).

---

That’s it—create the Show, wire two Seasons to their playlists, sync, and verify via Admin/API. The Flutter app will show Shows → Seasons (or jump straight to Episodes if only one season) and list videos with thumbnails.
