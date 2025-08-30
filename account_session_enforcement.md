# Account State Enforcement & Session Revocation — Spec

## What this is called
- **Session revocation** / **Account state enforcement**
- **Ban-aware auth** / **Server-driven logout**
- Often implemented with **JWT access + rotating refresh tokens**

---

## Goals
- If an account is **banned**, **deleted**, or **disabled**, the app:
  - Immediately **blocks access**, **clears tokens**, and **logs out**.
  - Shows a clear reason (“Account banned” / “Account deleted”).
- Backend can **invalidate sessions** instantly (no app update required).
- Prevent “zombie” sessions (stale tokens staying valid).

---

## Server Model (recommended fields)
- **users**:
  - `id` (UUID), `status` (`active|banned|deleted|disabled`), `banned_reason`, `deleted_at` (nullable), `token_version` (int, default 1), timestamps.
- **sessions** (refresh tokens):
  - `id` (UUID), `user_id`, `device_id` (install_id), `revoked_at` (nullable), `last_used_at`, `created_at`, `ip`, `user_agent`, **hash(refresh_token)**.
- **devices** (optional but useful):
  - `id` (UUID), `user_id`, `install_id` (UUID v4), `push_token`, `platform`, `app_version`, `last_seen_at`.
- **denylist** (for access-token `jti`):
  - `jti`, `exp`, TTL = `exp-now` (in-memory/Redis).

---

## JWT Strategy (high level)
- **Access token**: short-lived (5–15 minutes), includes:
  - `sub` (user id), `sid` (session id) **or** `jti` (token id), `tver` (**token_version**), `exp`, `iat`.
- **Refresh token**: long-lived (7–30 days), stored as **hashed** in DB, **rotated** on each refresh.
- **On refresh reuse detection**: revoke session family; require re-login.

---

## Revocation Mechanisms (use at least one; preferably two)
1. **Token-version bump (tver)**
   - Store `users.token_version` (int). Put `tver` in every access token.
   - If user is banned/deleted/disabled → **increment token_version**.
   - Any token with old `tver` becomes invalid at next request (server compares).
2. **Session store + rotation**
   - Each refresh token maps to a `sessions` row.
   - On **logout/ban/delete** → set `revoked_at` for all user sessions.
   - Middleware rejects any request whose `sid` is revoked or missing.
3. **Denylist by `jti` (optional)**
   - For immediate kill of specific access tokens before they expire.
   - Store `jti` in Redis with TTL until `exp`; reject if found.
4. **Back‑channel push (optional)**
   - Send a **revoke** message to device (FCM/APNs/WebSocket) to log out proactively without waiting for next API call.

---

## Request‑Time Enforcement (server)
- **Middleware** runs on every protected endpoint:
  - Load `user` and `session` from token claims (`sub`, `sid`/`jti`, `tver`).
  - Check **account status**: if `banned|deleted|disabled` → **403** `ACCOUNT_DISABLED` (include reason).
  - Check **token_version**: if `token.tver != users.token_version` → **401** `TOKEN_REVOKED`.
  - Check **session**: if `sessions.revoked_at` not null → **401** `TOKEN_REVOKED`.
  - Optional: if `jti` in denylist → **401** `TOKEN_REVOKED`.
- Always include structured error JSON with `code` and user‑readable message.

**Error codes (suggested)**
- `401 TOKEN_EXPIRED` — access token expired; client should try refresh flow.
- `401 TOKEN_REVOKED` — revoked/invalid; client must hard logout (no refresh).
- `403 ACCOUNT_DISABLED` — banned/disabled/deleted; logout + show reason.
- `426 APP_UPDATE_REQUIRED` — version gate (from your separate policy).

---

## Client Behavior (Flutter) — Interceptors
- Add a **global HTTP interceptor** around all API calls:
  - On **401 TOKEN_EXPIRED** → attempt refresh token; retry original request once.
  - On **401 TOKEN_REVOKED** **or** **403 ACCOUNT_DISABLED** →
    - **Clear** access/refresh tokens & sensitive caches.
    - **Unregister** push token (best‑effort call).
    - **Navigate** to Sign‑in; show short banner (“Session ended. Please sign in.” or reason).
    - **Stop** background tasks / streams.
- On app **resume**, ping a lightweight endpoint or rely on server response to enforce status.
- On **login**, store: `access_token`, `refresh_token`, `session_id`, `install_id`, `app_version`.

---

## Logout Flow (explicit user action)
1. Client calls `POST /api/v1/auth/logout` with current `session_id` **or** refresh token family id.
2. Server sets `sessions.revoked_at = now()` for that session; deletes push token binding.
3. Client **clears** tokens and in‑memory state; returns to Sign‑in.

---

## Ban / Delete Flow (server‑initiated)
- Admin sets `users.status = banned|deleted|disabled`, optionally `banned_reason`.
- Server runs:
  - `users.token_version += 1`
  - `revoke all sessions for user`
  - (optional) send **revoke** push to devices.
- Next client request (or push reception) triggers enforced logout.

---

## Minimal Endpoints
- `POST /api/v1/auth/login` → returns `{access_token, refresh_token, session_id, expires_in}`
- `POST /api/v1/auth/refresh` → rotate & return new tokens; detect reuse.
- `POST /api/v1/auth/logout` → revoke current session.
- `GET  /api/v1/me` → returns user profile/status (quick account-state probe).
- Admin: `POST /api/v1/admin/users/{id}/ban|disable|delete` → performs tver bump + revoke all.

---

## Storage & Security Notes
- Store **refresh tokens hashed** (like passwords). Never log tokens.
- Keep access tokens **short TTL**; rely on refresh for continuity.
- Rate‑limit login/refresh; IP + device key (`install_id`).  
- Consider device binding: refresh token tied to `install_id` and `platform`.
- Use HTTPS only; HSTS in production.

---

## Client Copy (UX)
- Banned: “Your account has been disabled. Reason: <reason>. Contact support.”
- Deleted: “This account no longer exists. You’ve been signed out.”
- Token revoked: “Session ended. Please sign in again.”

---

## Test Matrix
- Access expired → refresh succeeds → original request retried once.
- Access revoked (tver mismatch) → **401 TOKEN_REVOKED** → client hard‑logout.
- Session revoked (logout elsewhere) → **401 TOKEN_REVOKED** → hard‑logout.
- Account banned → **403 ACCOUNT_DISABLED** with reason → hard‑logout and message.
- Refresh reuse attack → server revokes session family → client must re‑login.
- Offline startup with cached token → first API returns enforcement → client logs out.

---

## Naming Cheatsheet
- “**Session revocation**”, “**Account state enforcement**”, “**Server‑driven logout**”, “**Ban‑aware session management**”.

