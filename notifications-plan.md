# Notifications Plan

## 1. Goals

- Unified, professional-grade notifications across **backend** and **Flutter app**.
- All pushes go through the backend, are logged in `UserNotification`, and are visible in the app inbox.
- Consistent **notification types** instead of free-form JSON.
- Backend admin chooses notification behavior from a **known list**, and the server generates the JSON `data` payload automatically.
- Flutter handles foreground/background notifications, navigation, and read state in a predictable way.

---

## 2. Current State (Summary)

### Backend

- Uses Firebase Admin SDK via `common/fcm_sender.py`:
  - `send_to_token`, `send_to_user`, `send_to_topic`.
  - Logs notifications in `onchannels.models.UserNotification`.
- Admin sending paths:
  - `/admin/auth/user/` test action → sends push via `send_to_user`.
  - `/admin/channels/usernotification/add/` (after customization) → on create, calls `send_to_user` and sends push.
  - `/admin/channels/schedulednotification/` → scheduled notifications via Celery (`enqueue_notification`).
- API endpoints:
  - `GET /api/onchannels/notifications/` → paginated inbox.
  - `POST /api/onchannels/notifications/mark-read/` → mark specific IDs as read.
  - `POST /api/onchannels/notifications/mark-all-read/` → mark all unread as read.

### Flutter

- `FcmManager`:
  - Initializes Firebase and obtains FCM token.
  - Registers the device with backend at `/user-sessions/register-device/`.
  - Foreground messages:
    - Shows a local notification (banner) via `FlutterLocalNotificationsPlugin`.
    - Saves a minimal in-app `NotificationItem` (title/body/link) to local storage.
- `NotificationInboxPage`:
  - Fetches backend notifications via `GET /channels/notifications/`.
  - Renders title/body/created_at.
  - Supports "Mark all read" via `POST /channels/notifications/mark-all-read/`.
  - Does **not yet** use `data` for navigation or per-item mark-read.

---

## 3. Notification Types (Selectable, Not Raw JSON)

Instead of hand-writing JSON in the admin, we define a **small set of notification types**. Admins pick a type and fill a few fields; the backend builds the `data` payload.

### 3.1 Canonical Types

Planned types (can be extended later):

1. **INBOX_MESSAGE**
   - Purpose: Generic message that opens the notification inbox.
   - Admin fields:
     - `user` (target user)
     - `title`
     - `body`
   - Generated `data`:
     ```json
     {
       "type": "inbox",
       "link": "/inbox"
     }
     ```

2. **SERIES_HIGHLIGHT**
   - Purpose: Highlight a specific series.
   - Admin fields:
     - `user`
     - `title`
     - `body`
     - `series_id_or_slug`
   - Generated `data`:
     ```json
     {
       "type": "series",
       "link": "/series/{id}",
       "id": "{id}"
     }
     ```

3. **SHORTS_RECOMMENDATION**
   - Purpose: Point the user to a specific short or shorts feed.
   - Admin fields:
     - `user`
     - `title`
     - `body`
     - `short_job_id` (optional; if empty, go to generic shorts page)
   - Generated `data`:
     - Specific job:
       ```json
       {
         "type": "shorts",
         "link": "/shorts/{job_id}",
         "id": "{job_id}"
       }
       ```
     - Generic shorts:
       ```json
       {
         "type": "shorts",
         "link": "/shorts"
       }
       ```

4. **LIVE_ALERT**
   - Purpose: Notify that a live channel is on.
   - Admin fields:
     - `user`
     - `title`
     - `body`
     - `channel_slug`
   - Generated `data`:
     ```json
     {
       "type": "live",
       "link": "/live/{slug}",
       "id": "{slug}"
     }
     ```

5. **SYSTEM_OR_SECURITY** (for future use)
   - Purpose: password resets, new device logins, important account alerts.
   - Admin fields:
     - `user`
     - `title`
     - `body`
   - Generated `data`:
     ```json
     {
       "type": "security",
       "link": "/inbox"
     }
     ```

The idea is: **no raw JSON entry required in admin**; the form will expose a choice field for `notification_type` and type-specific input fields. The server will build the JSON and store it in `UserNotification.data` and send it via FCM.

---

## 4. Backend Implementation Plan (Selectable Types)

### 4.1 Admin Form for UserNotification

- Add a custom `UserNotificationAdminForm` that wraps the existing model and introduces high-level fields:
  - `notification_type` (ChoiceField: INBOX_MESSAGE, SERIES_HIGHLIGHT, SHORTS_RECOMMENDATION, LIVE_ALERT, SYSTEM_OR_SECURITY).
  - `series_id_or_slug` (optional, only for SERIES_HIGHLIGHT).
  - `short_job_id` (optional, only for SHORTS_RECOMMENDATION).
  - `channel_slug` (optional, only for LIVE_ALERT).
- Hide or make `data` read-only in the admin form; it should be generated, not manually edited.
- In `clean()` or `save()`, construct `data` based on `notification_type` + extra fields.

### 4.2 Admin Save Behavior

- In `UserNotificationAdmin.save_model`:
  - For **new** notifications:
    - Use the cleaned form data to build `data` following the canonical patterns.
    - Call `send_to_user(user_id, title, body, data=generated_data)`.
    - Do **not** save the raw form instance again (to avoid duplicating the record `send_to_user` already creates).
  - For **edits** to existing notifications:
    - Allow editing of `title`/`body` if needed, but **do not resend** the push.

### 4.3 ScheduledNotification Integration (Optional)

- For batch/scheduled sending, reuse the same `notification_type` concept:
  - Either:
    - Add `notification_type` and type-specific fields to `ScheduledNotification`.
    - Generate the same `data` and use `send_to_user` / `send_to_topic`.

---

## 5. Flutter Implementation Plan

### 5.1 Navigation Based on Data

Implement a central function `handleNotificationNavigation(Map<String, dynamic> data)` that:

- If `data['link'] == '/inbox'` → navigate to `NotificationInboxPage`.
- If `data['type'] == 'series'` and `data['id']` present → navigate to series detail.
- If `data['type'] == 'shorts'` → open shorts screen, optionally for a specific job.
- If `data['type'] == 'live'` → open live player for `data['id']`.

Use this handler in:

- Foreground local notification tap callback.
- Background/terminated FCM initial-message handling in `main.dart`.
- Taps on items in `NotificationInboxPage` (using backend `data`).

### 5.2 Read State Sync

- Extend `NotificationInboxPage` to:
  - Read `id`, `data`, and `read_at` from each item.
  - Visually distinguish unread (`read_at == null`).
  - On tap of a row:
    - Call `POST /channels/notifications/mark-read/` with `{ "ids": [id] }`.
    - Call `handleNotificationNavigation(data)`.
    - Refresh the list.

### 5.3 Background/Terminated Notifications

- Wire up `FirebaseMessaging.onBackgroundMessage` in `main.dart`.
- On app start, check `FirebaseMessaging.instance.getInitialMessage()` and route via `handleNotificationNavigation` when the app was opened from a notification.

---

## 6. Error Handling and Observability

- **Backend**:
  - Ensure `send_to_user` logs failures and disables invalid tokens.
  - Admin should surface clear messages when a notification fails to send.
- **Client**:
  - Fail-safe: if `data` is missing or malformed, fall back to opening the inbox screen.
  - Log unexpected `type` values (for debugging) without crashing.

---

## 7. Rollout Strategy

1. Implement and test the new `UserNotification` admin form with selectable notification types in local dev.
2. Update Flutter to support `handleNotificationNavigation` and per-item mark-read.
3. Deploy backend and app updates to staging; send test notifications for each type.
4. Move to production once:
   - Foreground + background behavior is correct.
   - Read state sync works (individual and mark-all).
   - Admin UX for sending notifications is stable and easy to use.
