# Shorts Ingestion Pipeline — Execution To‑Do

Owner: Team
Date: 2025-10-28

Goal: Ingest permitted YouTube Shorts, transcode to HLS, store locally first (expandable pool), and serve reliably in-app without IFrame limits. Keep storage backend pluggable (S3/MinIO optional later).

## 1) Dependencies & Environment
- [x] System: install `ffmpeg`, `yt-dlp`
- [ ] Python deps: `django`, `celery`, `redis`, `tenacity` (plus `django-storages`/`boto3` only if enabling S3 later)
- [x] Configure Celery (broker URL, result backend), worker process, and beat (for periodic jobs)
- [x] Storage root (local): set Django `MEDIA_ROOT` to `/srv/media/short/videos`
  - Dev (macOS) override: `export MEDIA_ROOT="/Users/elu/media/short/videos"`
- [ ] Nginx: expose `/media/` with `alias` to the parent of `MEDIA_ROOT`; set HLS MIME types and CORS/cache headers
  - Example:
    ```nginx
    # HLS MIME types
    types {
      application/vnd.apple.mpegurl m3u8;
      video/mp2t ts;
    }

    # Serve media
    location /media/ {
      alias /srv/media/short/;  # parent of MEDIA_ROOT
      add_header Access-Control-Allow-Origin *;
      add_header Cache-Control "public, max-age=86400";
      expires 1d;
      # Optional: tune sendfile, buffers for large files
    }
    ```
- [x] Local dev Nginx: serving `/media/` on http://127.0.0.1:8080 (alias to `/Users/elu/media/short/`)
- [ ] Server (Ubuntu) Nginx: configure `/media/` on port 80 with alias to `/srv/media/short/`
- [x] Folder permissions: ensure app user can read/write within `MEDIA_ROOT`

## 2) Data Model
- [x] Model: `ShortJob`
  - id, created_at, updated_at
  - tenant, requested_by
  - source_url or (platform + video_id)
  - status: queued, downloading, transcoding, uploading, ready, retiring, deleted, failed
  - error_message, retry_count
  - artifact_prefix (e.g., `shorts/{tenant}/{job_id}`)
  - reserved_bytes, used_bytes
  - output: `hls_master_url`, duration, width/height, ladder_profile, variant_count
  - class: Pinned | Preferred | Normal | Ephemeral

## 3) API Endpoints (DRF)
- [x] POST `/api/channels/shorts/import/`
  - body: { source_url, ladder_profile: `shorts_v1|shorts_premium`, content_class }
  - returns: { job_id }
- [x] GET `/api/channels/shorts/import/{job_id}/`
  - returns: status, error, output URLs, bytes_reserved/used
- [ ] GET `/api/channels/shorts/import/{job_id}/preview/` (optional signed URL)
- [x] POST `/api/channels/shorts/import/{job_id}/retry/` (requeue failed jobs)
- [x] Admin: retry action for selected failed jobs

## 4) Pipeline Tasks (Celery)
- [x] Preflight (admission control)
  - Estimate bytes (ladder × duration) + 10% headroom
  - Enforce max duration 90s: default reject > 90s with clear error; optional admin override to trim to 90s (record original duration)
  - Check pool and per-tenant soft cap; atomic reserve `reserved_bytes`
- [x] Download (yt-dlp)
  - Output to temp dir; safe filenames; capture metadata (duration)
  - Idempotency: reuse if already downloaded and valid
- [x] Transcode (ffmpeg → HLS)
  - Ladder presets: `shorts_v1` = [480p, 720p]; `shorts_premium` = [480p, 720p, 1080p] (only for Preferred/Pinned)
  - Typical bitrates: 480p≈0.7 Mbps video, 720p≈1.5 Mbps, 1080p≈3.0 Mbps; audio AAC 128 kbps
  - Segment length 4–6s; generate master + variant playlists
- [x] Dedupe imports: reuse existing job by YouTube video_id within tenant
  - READY: return existing job_id (200)
  - IN-PROGRESS: return existing job_id for polling (202)
- [x] Ladder profile enforcement: 1080p only for Preferred/Pinned; downgrade non-priority `shorts_premium` to `shorts_v1`
- [ ] Upload (S3/MinIO)
  - Upload `master.m3u8`, variant playlists, segments
  - Set Content-Type and Cache-Control headers
  - If using S3/MinIO later: keep objects private and use signed URLs or CDN
- [x] Finalize
  - Convert `reserved_bytes` to `used_bytes`
  - Mark ready and store URLs/metadata
- [x] Cleanup temp
  - Always remove temp dirs; handle partials and retries safely

Status: Verified end-to-end on macOS dev. Ingested OfZ-x7dxnlA → READY (73s). HLS served via local Nginx at `/media/videos/shorts/ontime/<job_id>/master.m3u8`.

## 5) Storage Strategy
- [ ] Local-first: `MEDIA_ROOT` (`/srv/media/short/videos`) hosts `shorts/{tenant}/{job_id}/...`; Nginx serves `/media/` publicly (no signed URLs for now)
- [ ] Keep path stable even if you move pools; use per-short directory fan-out
- [ ] Optional later: enable S3/MinIO via `django-storages` without changing folder layout; add signed URLs/CDN as needed

## 6) Capacity & Policies
- [x] Global caps: soft/hard via env (defaults soft=9GB, hard=10GB)
- [x] Per-tenant quotas (defaults soft=3GB, hard=4GB), with class rules
  - Env:
    - `SHORTS_CAP_SOFT`, `SHORTS_CAP_HARD`
    - `SHORTS_TENANT_SOFT`, `SHORTS_TENANT_HARD`
    - `SHORTS_TENANT_<TENANT>_SOFT`, `SHORTS_TENANT_<TENANT>_HARD` (TENANT uppercased, dashes→underscores)
  - Class behavior:
    - Normal/Ephemeral: enforce soft and hard (fail if exceeded)
    - Preferred/Pinned: soft can be exceeded (logged), hard enforced
- [ ] Maximum duration per short: hard cap 90s (soft target ≤ 60s); reject > 90s by default; admin override can trim
- [ ] Ladder profiles: default `shorts_v1` (480p+720p); `shorts_premium` (add 1080p) only for Preferred/Pinned
- [ ] Atomic reservations to prevent overrun in parallel jobs
- [x] Atomic reservations: include existing reserved+used; reserve inside DB transaction
- [x] Low-water eviction: when above soft, purge Ephemeral → Normal → Preferred to low-water mark; skip Pinned
- [ ] Schedule eviction via Celery beat (e.g., every 15 min)

## 7) Lifecycle & Cleanup
- [ ] States: queued → downloading → transcoding → ready → retiring → deleted
- [ ] Classes: Pinned (never auto-purge), Preferred, Normal, Ephemeral
- [ ] Eviction policy when > soft cap:
  - Purge Ephemeral (oldest first) → Normal (LRU/oldest) → Preferred (oldest/unused)
  - Stop at low-water mark (e.g., 7.5–8 GB)
- [ ] Garbage collection: scan orphan temp/partials and remove
- [ ] Beat jobs: periodic cleanup, orphan sweep, metrics aggregation

## 8) Integrity & Security
- [ ] Temp workspace on same filesystem; atomic move to final path
- [ ] Hash at least the master playlist and one segment; store in DB
- [ ] At-rest encryption (SSE-S3/SSE-KMS or disk)
- [ ] Access: private objects; signed URLs; randomized paths
  - Local-first mode: public under Nginx (no signed URLs); later switch to tokenized/signed URLs without changing layout

## 9) Monitoring & Alerts
- [x] Structured logging per job/stage (start, preflight, download attempts, transcode per rendition, finalize)
- [ ] Counters/gauges (success/failure totals, disk usage) and export to metrics backend
- [ ] Alerts: warn at 80% (8 GB), severe at 90% (9 GB), block admissions ≥ 95%
- [ ] Dashboards: usage trend, ingestion rate vs deletion rate

## 10) Compliance & Governance
- [ ] License tracking: requester, permission proof, expiry
- [ ] Takedown: immediately retire + delete files and metadata
- [ ] Audit: pin/unpin, deletions, threshold changes with reasons
- [ ] YouTube/Platform compliance: ingest only permitted content

## 11) App Integration
- [ ] Player consumes our HLS master URL
- [ ] Handle retiring/deleted gracefully (skip/notify)
- [ ] Optional: pre-warm CDN for Pinned/Preferred content

## 12) Testing
- [ ] Unit tests: admission control, reservation conversion, ladder presets
- [ ] Integration: yt-dlp small sample, ffmpeg transcode, S3 upload, signed URLs
- [ ] Failure injection: network errors, disk full, ffmpeg/yt-dlp failures
- [ ] Cleanup tests: eviction order per class, low-water target

## 13) Configuration
- [x] `MEDIA_ROOT` = `/srv/media/short/videos`
  - Dev (macOS) override: `export MEDIA_ROOT="/Users/elu/media/short/videos"`
  - Celery worker/beat must inherit `MEDIA_ROOT` env
- [x] `SHORTS_CAP_SOFT`, `SHORTS_CAP_HARD` (global soft/hard)
- [x] `SHORTS_TENANT_SOFT`, `SHORTS_TENANT_HARD` (defaults, per-tenant fallback)
- [x] `SHORTS_TENANT_<TENANT>_SOFT`, `SHORTS_TENANT_<TENANT>_HARD` (per-tenant overrides)
- [ ] `SHORTS_LOW_WATER`

Production (20GB budget) suggested env:
- `SHORTS_CAP_SOFT=18GB`
- `SHORTS_CAP_HARD=20GB`
- `SHORTS_LOW_WATER=16GB`
- [ ] Ladder profiles (versioned): `shorts_v1` (480p,720p), `shorts_premium` (480p,720p,1080p)

---

Status Update (2025-10-29)
- [x] Admin metrics HTML complete
- [x] Batch import recent shorts endpoint complete
- [x] Celery broker/result: Redis at `redis://localhost:6379/2` with key prefix `celery-shorts:*`
- [ ] Nginx location `/media/` alias to `MEDIA_ROOT` parent (`/srv/media/short/`); HLS MIME types + CORS/cache
- [ ] Optional: Storage provider configs for S3/MinIO if enabled later

Yt-dlp/ffmpeg runtime:
- [x] Default yt-dlp client/headers: `--extractor-args youtube:player_client=android`, Android UA, and `Referer: https://www.youtube.com`
- [x] Format chain fallback: `bv*+ba / bestvideo[height<=720]+bestaudio / 18 / best<=720`
- [x] Optional env:
  - `YTDLP_COOKIES_FROM_BROWSER="firefox:<profile>"` or `YTDLP_COOKIES_FILE="/path/cookies.txt"`
  - `YTDLP_EXTRA_ARGS` for per-environment tuning (e.g., `--force-ipv4`)

## Open Questions
- [ ] Provider choice for prod (AWS S3 vs R2/Wasabi vs Spaces)
- [ ] CDN strategy now vs later
- [ ] Exact ladders/bitrates for your audience

