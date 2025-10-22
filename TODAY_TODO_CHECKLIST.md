# Ontime — Today’s Execution Checklist

Date: 2025-10-21
Owner: Team

## Goal
- Ship a vertical slice for push notifications (FCM) and finalize version release workflow end-to-end.

## Prereqs
- [ ] Create/confirm Firebase project and iOS/Android apps
- [ ] Download service account JSON (for backend sender)
- [ ] Add Apple push capability (APNs key/cert) in Firebase if sending to iOS

## Live Streams
- [x] Backend exposes live routes at `api/live/` via `authstack/live/urls.py` and included in `authstack/authstack/urls.py`
- [x] Flutter `LivePage` scaffold created at `Ontime_ethiopia_flutterapp/lib/live/live_page.dart`
- [x] Route registered in `lib/main.dart` as `'/live'`
- [x] Wire Home tab navigation to open `LivePage` (from `home/home_page.dart`)
- [x] Fetch live list from backend and render
- [x] Integrate playback via proxy endpoints: `GET /api/live/proxy/<slug>/manifest/`

## Flutter: Push + Version Gate
- [x] Add deps in `Ontime_ethiopia_flutterapp/pubspec.yaml`
  - [x] `firebase_core`, `firebase_messaging`
  - [x] Already present: `permission_handler`, `flutter_local_notifications`, `package_info_plus`
  - [x] Added `video_player` for HLS playback
- [x] Initialize Firebase in `lib/main.dart`
- [x] Request notification permission using `NotificationPermissionManager` (already exists)
- [x] Get FCM token and set refresh listener in `lib/core/notifications/fcm_manager.dart`
- [x] Persist token locally and prepare to sync with backend
- [x] Call backend device registration endpoint with `{ device_id, device_type, push_token, app_version }`
- [x] Add startup Version Gate call to `POST /api/channels/version/check/` and show dialogs/blocks
 - [x] Add background message handler in `lib/main.dart`

## Backend: Device Registration + Sender
- [x] Add endpoint to upsert `authstack/user_sessions/models.py::Device`
  - [x] URL: `POST /api/user-sessions/register-device/`
  - [x] Fields: `device_id`, `device_type (ios|android)`, `push_token`, `push_enabled=True`, last seen `app_version`
  - [x] Auth required; tenant-aware via `X-Tenant-Id`
- [x] Add Google FCM sender using `firebase_admin`
  - [x] Configure service account credentials (env variable / secret)
  - [x] Implement send-to-token and send-to-topic helpers
  - [ ] Handle invalid tokens; mark `push_enabled=False` on failures

## Subscriptions and Triggers
- [ ] Model/persist user subscriptions (like/follow) to shows
- [ ] On new show/episode publish: enqueue push to subscribers
  - [ ] Prepare concise payload: title, body, deep-link (optional)

## Scheduling (time-based notifications)
- [x] Add Celery + Redis + Celery Beat to `authstack/`
- [x] Create `ScheduledNotification` model with `title`, `body`, `send_at`, `audience` (topic/query)
- [ ] Admin form/API to create future sends
- [x] Beat task dispatches at `send_at`

## Version Release Workflow
- [ ] In Django Admin, create `AppVersion` per platform in `authstack/onchannels/version_models.py`
  - [x] Set `version`, `build_number/version_code`, `status`, `update_type`, `min_supported_version` (iOS)
  - [x] Store URLs: `ios_store_url` / `android_store_url` (iOS `store_url` present)
  - [ ] Add `changelog` and `features`
  - [ ] Repeat for Android
  
  - [x] Verify endpoint: `POST /api/channels/version/check/` returns forced update for iOS when `X-Tenant-Id: ontime` header is present
- **Curl example (with tenant header)**
  ```bash
  curl -s http://localhost:8000/api/channels/version/check/ \
    -H 'Content-Type: application/json' \
    -H 'X-Tenant-Id: ontime' \
    -d '{"platform":"ios","version":"1.0.0","build_number":1}'
  ```
- [x] Client calls `POST /api/channels/version/check/` on startup
- [x] (Optional) Send headers on every request: `X-App-Version`, `X-App-Platform`
- [x] (Optional) Add middleware to return HTTP 426 when `current < min_supported`

## Test Plan
- [x] Register device -> verify `Device.push_token` saved
- [x] Send test push to device -> receive foreground/background
- [ ] Create a show -> subscribers receive push
- [x] Create `ScheduledNotification` for +2 minutes -> delivered on time
- [x] Version gate: set `update_type=forced` on older version -> app blocks and opens store URL

## Stretch (if time permits)
- [ ] Topic strategy: one topic per show/channel; auto-subscribe on like/follow
- [ ] In-app settings toggles to opt-in/out of categories (releases, announcements)
- [ ] Analytics for push delivery + version 426 metrics

## Production Deploy
- [ ] Systemd: configure Celery worker/beat with `FIREBASE_CREDENTIALS_JSON` on server; enable on boot

## Enhancements
- [x] Add TTL and collapse key options to `fcm_sender` to avoid stale/duplicate notifications
- [x] Idempotency: prevent double-enqueue on repeated “Send now” clicks
- [ ] Add Sender API endpoint to create `ScheduledNotification` via POST

## Branding
- [ ] Add app notification icon/logo across Android and iOS (Android small status-bar icon `@mipmap/ic_notification`, iOS app/notification assets)

## Completed Today (Version Gate + First-Login Announcement)
- [x] Enforce min version at login/refresh (HTTP 426) in `authstack/common/middleware/version_enforce.py`
- [x] 426 blocking modal in Flutter with Update CTA and robust URL fallback in `lib/main.dart`
- [x] Removed duplicate update prompts (guarded `VersionGate.checkAndPrompt`) in `lib/main.dart`
- [x] Suppressed SnackBars for 426 across password and social login in `lib/api_client.dart` and `lib/auth/login_page.dart`
- [x] Backend endpoint `GET /api/channels/announcements/first-login/` implemented in `onchannels/version_views.py`
- [x] `Announcement` model created in `onchannels/notification_models.py` and registered in Admin (`onchannels/admin.py`)
- [x] Seeded tenant `ontime` announcement via data migration `onchannels/migrations/0008_seed_first_login_announcement.py`
- [x] Client fetches and shows backend announcement after successful login in `lib/auth/login_page.dart`

### Quick Verification
- [ ] Old app version: login returns 426; modal appears with disabled Update if `store_url` empty
- [ ] Up-to-date app: login succeeds; announcement dialog appears once after `me()`
- [ ] Admin: edit Channels → Announcements → First Login (tenant `ontime`); changes reflect in app

## Status Update (2025-10-21)
- **Version Gate**: working end-to-end (middleware 426 + Flutter modal).
- **Push (direct token)**: sending with FCM token works (server creds exported).
- **Push (send-to-user)**:
  - Backend helper `common/fcm_sender.send_to_user()` implemented (disables invalid tokens on error).
  - Admin action added on Users: “Send test push to selected users”.
  - Management command present but needs relocating under an installed app (e.g., `onchannels/management/commands/`) for `manage.py` discovery.
  - Action may fail for stale/mismatched tokens; ensure latest token is registered (uninstall/reinstall app to refresh) and Firebase project alignment (service account matches app project).

## Status Update (2025-10-22)
- **Social Login (iOS Google)**: Audience mismatch resolved by allowlisting iOS client ID in `authstack/authstack/settings.py::GOOGLE_WEB_CLIENT_IDS`. Pending server restart and retest on device.
- **Push (iOS device tokens)**: Recent sends report “Sent to 0 token(s)” for some users; need to confirm iOS token registration after login.

## iOS Google Sign-In Fix (Today)
- [x] Add iOS OAuth client ID to backend allowlist at `authstack/authstack/settings.py::GOOGLE_WEB_CLIENT_IDS`
- [x] Restart Django server to apply settings
- [ ] Ensure `ios/Runner/Info.plist` includes URL scheme from `ios/Runner/GoogleService-Info.plist` (`REVERSED_CLIENT_ID`)
- [x] Run app with `--dart-define=GOOGLE_IOS_CLIENT_ID=<ios-client-id>` and login
- [x] Verify `POST /api/social/login/` returns tokens; backend logs show accepted `aud`
- [x] Reorder Flutter Google flow: request notification permission before FCM registration

## iOS Push Token Registration
- [ ] Confirm FCM token retrieval on iOS after login and sync to backend via `POST /api/user-sessions/register-device/`
- [ ] In Django Admin, verify `Device.push_token` exists for the logged-in iOS user
- [ ] Send test push to that user; confirm receipt on device (foreground/background)
