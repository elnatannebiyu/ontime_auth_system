# Player & View Tracking — Backend Implementation Guide

This document describes a minimal, production-friendly backend design to:
- Use the official provider player (YouTube) so provider views are counted.
- Track your own first-party views (start/heartbeat/complete) for analytics.

Applies to Django app under `authstack/`.

---

## Goals
- First-party analytics: reliable per-episode view counts and watch-time.
- Provider-friendly: use official YouTube IFrame player; no raw file streaming for YT.
- Multi-tenant safe (via `X-Tenant-Id`) and authenticated.

## Existing Contract
- `GET /api/series/episodes/{id}/play/` → `{ episode_id, video_id, provider: 'youtube' }`
  - This continues to be the source of truth for playback identity.

## New Model: `EpisodeView`
Add to `authstack/series/models.py`:
- `tenant: CharField`
- `episode: ForeignKey(Episode)`
- `user: ForeignKey(User, null=True, blank=True)`
- `session_id: CharField(blank=True, default='')` (from your session model or device headers)
- `device_id: CharField(blank=True, default='')`
- `source_provider: CharField(default='youtube')`
- `playback_token: CharField(max_length=64)` (short-lived ID to correlate events)
- `started_at: DateTime`
- `last_heartbeat_at: DateTime(null=True)`
- `total_seconds: IntegerField(default=0)`
- `completed: BooleanField(default=False)`
- `ip: GenericIPAddressField(null=True, blank=True)`
- `user_agent: TextField(blank=True, default='')`
- Indexes: `(tenant, episode)`, `(tenant, started_at)`

## New Endpoints (all require IsAuthenticated + tenant filter)
Add to `authstack/series/views.py` (or a new `views_tracking.py`):

1) `POST /api/series/views/start`
Request:
```json
{
  "episode_id": 123,
  "playback_token": "<short-lived token>",
  "started_at": "2025-09-07T19:00:00Z",
  "device_id": "abcd-..."  // optional
}
```
Response:
```json
{ "view_id": 456 }
```
Behavior:
- Create an `EpisodeView` with zero seconds.
- Persist `ip` and `user_agent` from request.

2) `POST /api/series/views/heartbeat`
Request:
```json
{
  "view_id": 456,
  "playback_token": "<same token>",
  "seconds_watched": 15,
  "player_state": "playing",  // playing | paused | buffering
  "position_seconds": 120       // optional, aids debugging
}
```
Response:
```json
{ "ok": true }
```
Behavior:
- Increment `total_seconds` by `seconds_watched` (server-side clamp to sane ranges, e.g., 0..120).
- Update `last_heartbeat_at`.

3) `POST /api/series/views/complete`
Request:
```json
{
  "view_id": 456,
  "playback_token": "<same token>",
  "total_seconds": 1200,
  "completed": true
}
```
Response:
```json
{ "ok": true }
```
Behavior:
- Mark `completed = true` (idempotent).
- Update `total_seconds` to max(existing, provided) to avoid regressions.

### Security & Validation
- Validate that `EpisodeView.tenant == request.tenant`.
- Validate `playback_token` matches the one issued for the `view_id`.
- Enforce user/session/device consistency if available.
- Rate-limit heartbeats (e.g., 4 req/minute per view) via DRF throttling.

## Generating `playback_token`
- Option A: return a random UUID from `/play/` and store it server-side per user/session/episode.
- Option B: return a short-lived signed token (JWT) containing `tenant`, `episode_id`, `user_id/session_id`, expire 1 hour.

## Aggregations
- Nightly job to roll up raw `EpisodeView` rows into show/season/episode metrics (view_count, unique_viewers, total_watch_time, completion_rate).

## Episode Ordering (already implemented)
- Default: `episode_number ASC (nulls last)`, `source_published_at`, `id`.
- Override with `?ordering=` if needed.

## Absolute Cover URLs (already implemented)
- `ShowSerializer.cover_image` and `SeasonSerializer.cover_image` resolve to absolute URLs using `request.build_absolute_uri`.

---

## Minimal DRF Stubs (pseudo)
```python
# series/views_tracking.py
from rest_framework import views, permissions, status
from rest_framework.response import Response
from .models import Episode, EpisodeView

class ViewStartAPI(views.APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        tenant = request.headers.get('X-Tenant-Id')
        ep_id = request.data.get('episode_id')
        token = request.data.get('playback_token')
        # validate ep exists and tenant matches
        # create EpisodeView; return view_id
        return Response({"view_id": 1}, status=status.HTTP_201_CREATED)

class ViewHeartbeatAPI(views.APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        # load view by id+token+tenant; increment seconds; return ok
        return Response({"ok": True})

class ViewCompleteAPI(views.APIView):
    permission_classes = [permissions.IsAuthenticated]
    def post(self, request):
        # mark completed; bump total_seconds
        return Response({"ok": True})
```

Add URLs in `series/urls.py`:
```python
from django.urls import path
from .views_tracking import ViewStartAPI, ViewHeartbeatAPI, ViewCompleteAPI
urlpatterns += [
    path('views/start', ViewStartAPI.as_view()),
    path('views/heartbeat', ViewHeartbeatAPI.as_view()),
    path('views/complete', ViewCompleteAPI.as_view()),
]
```

---

## Testing
- Unit tests for start/heartbeat/complete (auth, tenant, token).
- Integration: ensure `/play/` + start + heartbeat + complete roundtrip.
- Rate-limit tests to prevent spam.
