# Ontime — Tomorrow’s Execution Checklist (Shorts Feature)

Date: 2025-10-22
Owner: Team

## Goal
- Add a Shorts experience to the Home screen. Fetch “shorts” playlists per channel, bias to most recent first, then randomized order per user/device. Limit to recently updated playlists (last 30 days) and reasonable caps.

## Scope
- New Home tab “Shorts”.
- Backend feed endpoints with tenant awareness and recent-update filters.
- Client page, service layer, and playback list logic with recent-first bias and per-device/user randomization.

## Backend
- [x] Add endpoint: `GET /api/channels/shorts/playlists/`
  - [x] Query playlists labeled `shorts` for all channels within last 30 days
  - [x] Params: `updated_since`, `limit`, `offset`, `per_channel_limit`
  - [x] Tenant-aware via `X-Tenant-Id`
  - [x] Order: `-updated_at` by default
- [x] Add endpoint: `GET /api/channels/shorts/feed/`
  - [x] Inputs: `device_id` (header), `user_id` (from auth), optional `seed`
  - [x] Strategy: take recent playlists first, then shuffle remaining deterministically by `(seed || device_id || user_id)`
  - [x] Caps: total playlists (e.g., 100), per-channel cap (e.g., 5)
  - [x] Return normalized items: `{channel, playlist_id, title, updated_at, items_count}`
- [x] Unit tests: filters (30-day window), per-channel limits, deterministic randomization

### Backend (Ingestion Pipeline)
- [ ] Dependencies and setup
  - [ ] Install system deps: `ffmpeg`, `yt-dlp`
  - [ ] Add Python deps: `celery`, `redis` (or `rabbitmq`), `boto3`, `django-storages`
  - [ ] Configure Celery app, broker, and worker Procfile/commands
- [ ] Models
  - [ ] `DownloadJob`: id, tenant, requested_by, source_url/video_id, status (queued/downloading/transcoding/uploading/ready/failed), error_message, retry_count, artifact_prefix, output URLs
- [ ] Celery tasks
  - [ ] Task: download with yt-dlp to temp dir (idempotent, safe filenames)
  - [ ] Task: optional transcode to HLS with ffmpeg (master + variants)
  - [ ] Task: upload to S3 (content-type, cache-control) and finalize
  - [ ] Cleanup temp files; record duration/size/resolution
- [ ] Storage
  - [ ] Configure S3 or MinIO, bucket layout: `shorts/{tenant}/{job_id}/...`
  - [ ] Private objects + signed URLs or CDN (CloudFront) config
- [ ] API endpoints (DRF)
  - [ ] POST `/api/shorts/import/` (body: url/video_id, options) → returns `{job_id}`
  - [ ] GET `/api/shorts/import/{job_id}/` → status/progress/output
  - [ ] GET `/api/shorts/import/{job_id}/preview/` → signed master.m3u8 (optional)
- [ ] Admin/UI
  - [ ] List/retry/purge jobs in Django Admin
- [ ] Controls and quotas
  - [ ] Per-tenant daily caps, max duration/size, allowed domains
  - [ ] Automatic retries for transient errors
- [ ] Compliance & audit
  - [ ] Store requester, source link, consent notes
  - [ ] Document TOS and permitted content policy

## Flutter (App)
- [ ] Create `lib/shorts/shorts_page.dart` patterned after `lib/channels/shows_page.dart`
- [ ] Wire Home tab to new Shorts page (label already changed in `lib/home/home_page.dart`)
- [ ] Add service `lib/channels/shorts_service.dart`
  - [ ] `fetchRecentPlaylists({days=30, perChannel=5, limit=100})`
  - [ ] `fetchShortsFeed()` consuming `/shorts/feed/`
- [ ] Implement ordering in client (as fallback when feed endpoint not available)
  - [ ] Sort by `updated_at` desc, then deterministic shuffle with stable seed (device/user)
- [ ] Playback UX
  - [ ] Autoplay next short; simple controls (mute/unmute, next)
  - [ ] Handle empty state (no recent playlists)

### YouTube Interactions (Phase 2)
- [ ] Google account linking (in addition to app login)
  - [ ] Implement Google Sign-In (iOS/Android) with YouTube scope `youtube.force-ssl`
  - [ ] Persist and refresh Google OAuth tokens (securely)
- [ ] Backend proxy endpoints
  - [ ] POST `/api/yt/videos/rate` -> YouTube `videos.rate` (like/dislike)
  - [ ] POST `/api/yt/comments/insert` -> `commentThreads.insert`/`comments.insert`
  - [ ] GET `/api/yt/comments/list` -> `commentThreads.list`
- [ ] App UI wiring
  - [ ] Show Like/Dislike as disabled until Google account is linked
  - [ ] Enable actions once linked; error handling for quota/auth failures
  - [ ] Open in YouTube (deep link) and native Share sheet remain as fallbacks

## Limits & Config
- [ ] Default recent window: 30 days (server default; client can override)
- [ ] Per-channel playlist cap (e.g., 5)
- [ ] Total feed cap (e.g., 100)

## Telemetry (Optional, if time permits)
- [ ] Emit events: `short_view_start`, `short_next`, `short_like`, `short_dislike`
- [ ] Use events to adjust future shuffle bias (out of scope for tomorrow if time is tight)

## Deliverables
- [x] Backend endpoints documented in `API_ENDPOINTS.md`
- [ ] Flutter Shorts page navigable from Home tab
- [ ] Feed visible with recent-first then randomized ordering

## Test Plan
- [x] Curl: `/api/channels/shorts/playlists/` returns only 30-day updated items and respects limits
- [x] Curl: `/api/channels/shorts/feed/` changes order deterministically with a fixed `seed`
- [ ] App: Shorts tab loads and plays through list; next/prev works; empty state covered
- [x] Tenant header required; authenticated flow works

## Nice to Have (time permitting)
- [ ] Pull-to-refresh on Shorts page
- [ ] Persist last watched position per device (optional)
- [ ] Topic subscription for new short uploads (future)
