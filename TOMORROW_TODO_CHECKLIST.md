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
- [ ] Add endpoint: `GET /api/channels/shorts/playlists/`
  - [ ] Query playlists labeled `shorts` for all channels within last 30 days
  - [ ] Params: `updated_since`, `limit`, `offset`, `per_channel_limit`
  - [ ] Tenant-aware via `X-Tenant-Id`
  - [ ] Order: `-updated_at` by default
- [ ] Add endpoint: `GET /api/channels/shorts/feed/`
  - [ ] Inputs: `device_id` (header), `user_id` (from auth), optional `seed`
  - [ ] Strategy: take recent playlists first, then shuffle remaining deterministically by `(seed || device_id || user_id)`
  - [ ] Caps: total playlists (e.g., 100), per-channel cap (e.g., 5)
  - [ ] Return normalized items: `{channel, playlist_id, title, updated_at, items_count}`
- [ ] Unit tests: filters (30-day window), per-channel limits, deterministic randomization

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

## Limits & Config
- [ ] Default recent window: 30 days (server default; client can override)
- [ ] Per-channel playlist cap (e.g., 5)
- [ ] Total feed cap (e.g., 100)

## Telemetry (Optional, if time permits)
- [ ] Emit events: `short_view_start`, `short_next`, `short_like`, `short_dislike`
- [ ] Use events to adjust future shuffle bias (out of scope for tomorrow if time is tight)

## Deliverables
- [ ] Backend endpoints documented in `API_ENDPOINTS.md`
- [ ] Flutter Shorts page navigable from Home tab
- [ ] Feed visible with recent-first then randomized ordering

## Test Plan
- [ ] Curl: `/api/channels/shorts/playlists/` returns only 30-day updated items and respects limits
- [ ] Curl: `/api/channels/shorts/feed/` changes order deterministically with a fixed `seed`
- [ ] App: Shorts tab loads and plays through list; next/prev works; empty state covered
- [ ] Tenant header required; authenticated flow works

## Nice to Have (time permitting)
- [ ] Pull-to-refresh on Shorts page
- [ ] Persist last watched position per device (optional)
- [ ] Topic subscription for new short uploads (future)
