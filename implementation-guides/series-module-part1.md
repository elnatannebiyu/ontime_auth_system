# Series & Notifications Implementation – Part 1 (Backend Analysis + Naming Contracts)

This Part 1 guide captures the CURRENT backend architecture and locks naming + patterns for the upcoming `series/` and `integrations/` apps. It ensures we implement new features consistently with existing middleware, auth, permissions, and YouTube helpers.

## A. Current Backend Snapshot (authstack/)

- Apps in use:
  - `accounts/`: JWT auth with cookies, sessions, roles. Views in `accounts/views.py`, URLs in `accounts/urls.py`.
  - `onchannels/`: Channels/Playlists/Videos + YouTube helpers and admin sync actions. Views in `onchannels/views.py`.
  - `otp_auth/`: OTP endpoints at `/api/auth/otp/`.
  - `common/tenancy.py`: `TenantResolverMiddleware` requires `X-Tenant-Id` for all `/api/*`.

- Settings (`authstack/authstack/settings.py`):
  - DRF auth: `accounts.jwt_auth.CustomJWTAuthentication`.
  - Throttling, Axes brute-force, CORS.
  - SimpleJWT configured; refresh in httpOnly cookie.
  - Swagger (drf_yasg) with Bearer and X-Tenant-Id security schemes.
  - YouTube API key via `settings.YOUTUBE_API_KEY`.

- URL roots (`authstack/authstack/urls.py`):
  - `/api/` → `accounts/urls.py`
  - `/api/channels/` → `onchannels/urls.py`
  - `/api/auth/otp/` → `otp_auth/urls.py`
  - Swagger at `/swagger/` and `/redoc/` (public).

- `onchannels` patterns:
  - Models: `Channel`, `Playlist`, `Video` in `onchannels/models.py`.
  - Read-only viewsets for Channel/Playlist/Video with `IsAuthenticated` + tenant filtering by header.
  - Admin-only actions under `ChannelViewSet` for syncing playlists/videos from YouTube.
  - YouTube helpers in `onchannels/youtube_api.py` (resolve channel, list playlists/items, get playlist).

## B. Names, Conventions, and Policies to Reuse

- Authentication: `Authorization: Bearer <access>` + refresh via cookie. Do not invent new auth patterns.
- Tenancy: Require `X-Tenant-Id` on all `/api/*`. Always enforce object-level `tenant` matching.
- Permissions: Default `IsAuthenticated` for read; write endpoints gated by explicit Django permissions.
- Error responses:
  - Use `{ "detail": "..." }` for general errors.
  - Social views uniquely expect `{ "error": "..." }` (unchanged).
- Swagger: Include `X-Tenant-Id` as a required header via `@swagger_auto_schema(manual_parameters=[...])`.
- Pagination + ordering: Prefer DRF defaults; expose `ordering` query params for lists.

## C. New Apps to Add (Scope of Part 2+)

- `series/` (content layer):
  - Models: `Show`, `Season`, `Episode` (tenant-aware). One Season = one YouTube playlist.
  - Admin: enable/disable Season; approve/hide/fix episode numbers; “Run Sync Now.”
  - APIs: Read-only for Flutter; admin-only write actions and sync.
- `integrations/` (secure keys & providers):
  - Model: `IntegrationConfig` (encrypted secrets) per tenant/provider (FCM, YouTube, etc.).
  - Admin validation + test buttons; runtime resolver with caching.

## D. Minimal YouTube API Strategy (Confirmed)

- Initial Season mapping: `playlists.list` (1 unit) + `playlistItems.list` tail pages (1–3).
- “Sync now”: `playlists.list` heartbeat → if itemCount increased, fetch only the tail pages; stop at first known `videoId`.
- Avoid `search.list`; batch `videos.list` by ≤50 IDs only if you need durations.

## E. Notifications (Confirmed Policies)

- Subscriptions: per-user `SeasonSubscription`; excludes trailers by default; user can opt-in to trailer alerts.
- Devices: `UserDevice` for delivery (FCM/APNs), not for subscription.
- Quiet hours: defer 22:00–08:00 Africa/Addis_Ababa; queue and deliver at 08:00 local.
- Event flow: `sync_season` detects new episode → create `NotificationEvent` → fan-out to subscribed users’ active devices. Idempotent by `(tenant, season, video_id)`.
- Playback: Embedded YouTube by default; “Open in YouTube” option; API never returns full watch URLs.
- Scheduler: Start with cron + management command; move to Celery + Redis later.

## F. Exact Naming Contracts (to avoid future rename churn)

- App labels:
  - `series` (content layering app)
  - `integrations` (keys/config)

- Models (series/models.py):
  - `Show` (fields: `tenant`, `slug`, `title`, `synopsis`, `cover_image`, `default_locale`, `tags`, `channel`, `is_active`, timestamps)
  - `Season` (fields: `tenant`, `show`, `number`, `title?`, `cover_image?`, `is_enabled`, `yt_playlist_id`, `include_rules` JSON, `exclude_rules` JSON, `last_synced_at`)
  - `Episode` (fields: `tenant`, `season`, `source_video_id`, `source_published_at`, `duration?`, `thumbnails` JSON, `episode_number?`, `title`, `description`, `title_override?`, `description_override?`, `publish_at?`, `visible`, `status` in {`published`,`needs_review`,`draft`})

- Models (notifications within series/ or notifications/ subapp):
  - `UserDevice` (fields: `tenant`, `user`, `platform`, `token`, `device_id?`, `app_version?`, `locale?`, `is_active`, `last_seen_at`, timestamps)
  - `SeasonSubscription` (fields: `tenant`, `user`, `season`, `include_trailers`(bool), timestamps; unique `(tenant,user,season)`)
  - `NotificationEvent` (fields: `tenant`, `kind` in {`NEW_EPISODE`,`NEW_TRAILER`}, `show`, `season`, `episode?`, `payload` JSON, `status`, `attempts`, `scheduled_for?`, timestamps)
  - `NotificationDelivery` (fields: `event`, `user`, `device`, `status` in {`pending`,`sent`,`failed`,`suppressed`}, `error?`, `sent_at`, `dedupe_key`)

- Permissions (Django perms):
  - `series.manage_content` required for write actions (admin UI + write endpoints)
  - Read endpoints: `IsAuthenticated`

- URL base prefixes:
  - `series/urls.py` included at `/api/series/`
  - Read endpoints (Flutter):
    - `GET /api/series/shows/`
    - `GET /api/series/shows/{slug}/`
    - `GET /api/series/shows/{slug}/seasons/`
    - `GET /api/series/seasons/{season_id}/episodes/`
    - `GET /api/series/episodes/{episode_id}/`
    - `GET /api/series/episodes/{episode_id}/play/`
  - Admin actions:
    - `POST /api/series/seasons/{id}/sync/`
    - `POST /api/series/seasons/{id}/reorder/`
  - Notifications (user-level):
    - `POST /api/series/devices/register/`
    - `POST /api/series/devices/unregister/`
    - `POST /api/series/seasons/{season_id}/subscribe/`
    - `POST /api/series/seasons/{season_id}/unsubscribe/`
    - `GET /api/series/subscriptions/`

- Serializer patterns:
  - For list items include a `display_title` derived on the server: `title_override or title`.
  - Never include full YouTube URLs; include only `video_id` and thumbnails.

- Error shapes:
  - Use `{ "detail": "..." }` for errors in series and notifications endpoints.

- Swagger:
  - Each view or action uses `@swagger_auto_schema(manual_parameters=[PARAM_TENANT])`, following `onchannels/views.py`.

## G. Part 2 (What we implement next)

- Scaffold `series/` app with models and admin.
- Scaffold `integrations/IntegrationConfig` with encrypted storage + admin validations.
- Wire `/api/series/` urls (read endpoints only in Part 2), add Swagger docs.
- Implement `sync_season` management command using the minimal YouTube pattern.
- Unit tests for model validations and the command’s basic flow.

This Part 1 locks the names, URLs, perms, and behaviors so we can implement safely without refactors. If you want any changes to naming, now is the time; otherwise I’ll proceed to Part 2 (scaffolding + migrations).
