# Series Module (Shows/Seasons/Episodes) – Implementation Guide

This document defines the plan to add a series layer on top of existing YouTube `Playlist`/`Video` data in `onchannels/`. The goal is to manage series seasons and episodes like a TV channel, hide raw YouTube URLs from clients, and auto-sync new episodes.

## Goals
- Treat content as Series → Seasons → Episodes.
- One Season = one YouTube playlist (default, simple, deterministic).
- Admin-only CRUD via web admin/API. Flutter app is read-only.
- Hide full YouTube URLs. Expose only `video_id` and safe playback configs.
- Auto-sync on a schedule with inclusion/exclusion rules.
- Multitenant and channel-scoped, aligned with `X-Tenant-Id`.

## New Django App
- Name: `series` (separate from `onchannels`).
- Depends on `onchannels` models for source mapping (`Playlist`, `Video`).

## Data Model
All models include tenant scoping and timestamps.

- Show
  - tenant (char or FK to tenant model), slug (unique per tenant)
  - title, synopsis, cover_image, default_locale, tags (JSON)
  - channel (FK to `onchannels.Channel`) for origin context
  - is_active (bool)

- Season
  - show (FK)
  - number (int) and optional title
  - cover_image, is_enabled (bool)
  - yt_playlist_id (char, references `onchannels.Playlist.id`)
  - include_rules (JSON list of regex), exclude_rules (JSON list of regex)
  - last_synced_at (datetime)

- Episode
  - season (FK)
  - source_video_id (YouTube `video_id`, references `onchannels.Video.video_id` logically)
  - source_published_at (datetime), duration (sec, optional), thumbnails (JSON)
  - episode_number (int, nullable; can be overridden)
  - title, description (pulled from source)
  - title_override, description_override (admin editorial)
  - publish_at (datetime, optional editorial embargo)
  - visible (bool), status (enum: draft|published|needs_review)

Notes
- Keep Episodes referencing the source by `video_id` to remain flexible.
- Add DB indexes on `(season, episode_number)`, `(season, source_published_at)`.

## Inclusion/Exclusion Rules
- Default exclusion keywords (case-insensitive): `trailer|teaser|promo|shorts|clip`.
- Admin can override per Season via `include_rules` and `exclude_rules` (regex list evaluated with OR semantics).

## Episode Number Parser
Parsing precedence used to assign `episode_number` during sync (when playlist positions are unreliable):
1) Playlist position (primary ordering)
2) Regex from title (case-insensitive):
   - `(?:E|Ep|Episode)[\s\-_.]*([0-9]+)`
   - `S[0-9]+[\s\-_.]*E([0-9]+)`
   - `Part[\s\-_.]*([0-9]+)` (optional)
   - Bare trailing `([0-9]+)$` guarded by season title match
3) Fallback to `source_published_at` ascending.

## API Design
Base path: `/api/series/` (new `series/urls.py` included from project `urls.py`). All endpoints require `X-Tenant-Id` (middleware already enforces) and default to `IsAuthenticated`.

Public (Flutter – READ ONLY)
- GET `/api/series/shows/` → List Shows (active, tenant-filtered)
- GET `/api/series/shows/{slug}/` → Show detail with Season summary
- GET `/api/series/shows/{slug}/seasons/` → List Seasons for a Show
- GET `/api/series/seasons/{season_id}/episodes/` → List Episodes (published & visible)
- GET `/api/series/episodes/{episode_id}/` → Episode detail (no full URL)
- GET `/api/series/episodes/{episode_id}/play/` → Playback config { video_id, player_params, token }

Admin (Web – CRUD)
- Shows: CRUD endpoints
- Seasons: CRUD + set `yt_playlist_id`, rules, enable/disable
- Episodes: Edit `episode_number`, titles/overrides, visibility, status; reorder
- Actions:
  - POST `/api/series/seasons/{id}/sync/` (manual sync)
  - POST `/api/series/seasons/{id}/reorder/` with list of episode IDs → new order/episode_numbers

Permissions
- Default permission classes: `IsAuthenticated` + custom `IsSeriesAdmin` for writes
- Role mapping: reuse existing role/permission pattern (e.g., `onchannels.manage_content` or `series.manage_content` Django permission)
- Flutter app has no write permissions; enforce at backend via roles/permissions. Optionally validate client type header if needed.

Response Shape (examples)
- Episode list item:
  ```json
  {
    "id": "uuid",
    "episode_number": 12,
    "title": "Episode 12",
    "title_override": null,
    "display_title": "Episode 12", // derive server-side: override or title
    "thumbnails": {"default": "..."},
    "publish_at": "2025-09-07T10:00:00Z",
    "visible": true,
    "status": "published"
  }
  ```
- Playback:
  ```json
  { "video_id": "YTvID123", "player_params": { "start": 0 }, "token": "short-lived" }
  ```

## Sync Pipeline
Phase 1 (cron + management command)
- Management command: `python manage.py sync_season --season=<id|slug>` (supports `--tenant`, `--dry-run`)
- Steps:
  1. Resolve Season → `yt_playlist_id`
  2. Fetch playlist items via existing YouTube client (`onchannels/youtube_api.py`)
  3. Apply inclusion/exclusion rules
  4. Map to Episodes by `video_id`
  5. Determine `episode_number` (position → parser → publish date)
  6. Upsert Episodes; set status:
     - `published` if rule-matched and no conflicts
     - `needs_review` if parser failed or number collision
  7. Update `last_synced_at`

Phase 2 (Celery + Redis)
- Celery tasks per Season with retries/backoff
- Celery Beat schedules (e.g., every 15 minutes)
- Per-tenant routing optional

## URL Hiding & Playback
- API must never return `https://youtube.com/...` URLs.
- Only expose `video_id` and a short-lived token/player params from `/play/` endpoint.
- Web and mobile clients load the YouTube player using `video_id`.

## Admin/UI
- Django Admin: Register Show, Season, Episode with list filters (tenant, channel, status), inlines for Seasons and Episodes under Show.
- Swagger: Document all endpoints and required `X-Tenant-Id` and Bearer token.

## Security & Multi-Tenancy
- Enforce `X-Tenant-Id` via existing middleware (`common.tenancy.TenantResolverMiddleware`).
- Add object-level checks to ensure Show/Season/Episode tenant matches `request.tenant`.
- Write ops require `series.manage_content` permission (assign to Administrator role by default).

## Migrations & Seeding
- Create migrations for new models.
- Seed example Show/Season entries per tenant for quick validation.

## Testing
- Unit tests: parser regex, inclusion rules.
- API tests: permissions (admin vs regular), list/detail, playback endpoint.
- Sync tests: creates/updates episodes; handles duplicates; flags `needs_review`.

## Rollout Plan
1) Implement models + admin
2) Implement read-only public APIs for Flutter
3) Implement admin APIs + permissions
4) Add management command and test with one Season
5) Optional: add Celery for scheduled sync
6) Update documentation and Swagger

## Future Enhancements
- Support multiple playlists per Season (2A/2B) if needed
- Amharic numerals parsing
- Editorial bundles (featured episodes)
- Per-platform visibility rules

## Push Notifications (Server-side)

Design to notify users when a new episode (or trailer, if included) is available. This is tenant-aware and respects the read-only constraint for Flutter (Flutter can register device tokens and subscribe/unsubscribe; no content CRUD).

### Objectives
- Store device tokens per user/device (FCM, and APNs via FCM if preferred).
- Allow users to subscribe to a Season (playlist) for “Remind me”.
- Ingest/sync detects NEW_EPISODE (and optionally NEW_TRAILER) and creates Notification Events.
- A fan-out worker delivers push notifications to all subscribers with a deep link to the episode.

### Data Model (New)
- UserDevice
  - user (FK), tenant (char/FK), platform (android|ios|web), token (text, unique per platform if possible), device_id, app_version, locale
  - is_active (bool), last_seen_at (datetime), created_at/updated_at
  - Index on (tenant, user), (tenant, token)

- SeasonSubscription
  - user (FK), tenant, season (FK to `series.Season`), created_at
  - unique_together (user, tenant, season)

- NotificationEvent
  - tenant, kind (NEW_EPISODE|NEW_TRAILER), show (FK), season (FK), episode (FK, nullable for trailer), payload (JSON: titles, numbers, thumbnails), created_at
  - status (queued|processing|completed|failed), attempts (int), scheduled_for (datetime, optional)

- NotificationDelivery
  - event (FK), user (FK), device (FK), status (pending|sent|failed|suppressed), error (text), sent_at
  - dedupe_key (e.g., f"{event_id}:{device_id}") to avoid duplicates

### API Endpoints
All endpoints require `X-Tenant-Id` and `IsAuthenticated`.

- POST `/api/series/devices/register/`
  - Body: { platform, token, device_id?, app_version?, locale? }
  - Upserts `UserDevice` for the user/tenant.

- POST `/api/series/devices/unregister/`
  - Body: { token }
  - Marks device inactive.

- POST `/api/series/seasons/{season_id}/subscribe/`
  - Creates `SeasonSubscription` for current user.

- POST `/api/series/seasons/{season_id}/unsubscribe/`
  - Deletes subscription.

- GET `/api/series/subscriptions/`
  - Lists user’s season subscriptions for the tenant.

Permissions:
- All above are user-level operations. Use `IsAuthenticated` and tenant checks. No admin role required.

### Ingest Integration (Event Creation)
- During `sync_season`:
  1. Detect episodes newly created or newly published (status transitions to published).
  2. If trailers are not excluded and detected as new, create NEW_TRAILER events.
  3. Create `NotificationEvent` rows with episode metadata for each new item.
  4. Enqueue Celery task: `notifications.fanout_event(event_id)`.

### Fan-out Worker (Celery Task)
- Query all `SeasonSubscription` for the event’s season and tenant.
- For each subscribed user, fetch active `UserDevice` rows.
- Create `NotificationDelivery` rows; send push via FCM:
  - Title: `New Episode: S{season.number}E{episode_number}` (localized if possible)
  - Body: Episode or show title
  - Data payload: { deeplink, tenant, show_slug, season_id, episode_id }
- Handle retries with exponential backoff on transient errors.
- Mark deliveries `sent`/`failed` and roll up status on the `NotificationEvent`.

### Provider Integration
- FCM server key via env (`FCM_SERVER_KEY`). For iOS, either APNs via FCM or direct APNs if required later.
- Implement sender service with minimal dependency and clear logging. Batch sending when possible.

### Deep Link Format
- Universal format that both web and mobile can interpret:
  - `ontime://series/episodes/{episode_id}`
  - Web fallback: `https://app.ontime.tv/s/episodes/{episode_id}`
- Backend playback endpoint already exposes `video_id`; clients resolve the deeplink to open the episode screen and request playback.

### Anti-Spam and Preferences
- Per-user mute settings (future): quiet_hours, opt-out from trailers, max_notifications_per_day.
- Dedupe: avoid sending multiple notifications for the same episode/device (use `NotificationDelivery.dedupe_key`).

### Admin and Monitoring
- Admin list views for Events and Deliveries with filters (tenant, status, kind, season).
- Metrics/logging: counts of queued/sent/failed, device churn, token invalidation rates.

### Testing
- Unit tests: device register/unregister, subscribe/unsubscribe, fanout rendering.
- Integration tests: sync creates events, fanout delivers to subscribed devices, failure handling.
