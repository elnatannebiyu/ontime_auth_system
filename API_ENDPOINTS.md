# Complete API Endpoints Documentation

## Base URL
- Development: `http://localhost:8000/api/`
- All endpoints require `X-Tenant-Id` header (e.g., `X-Tenant-Id: default`)

## Authentication Endpoints

### 1. Login
- **POST** `/api/token/`
- **Body:** `{ "username": "string", "password": "string" }`
- **Response:** `{ "access": "jwt_token", "refresh": "jwt_token" }`
- **Rate Limit:** 5 attempts/minute
- Sets refresh token in httpOnly cookie

### 2. Token Refresh
- **POST** `/api/token/refresh/`
- **Cookie:** Requires refresh_token cookie
- **Response:** `{ "access": "new_jwt_token", "refresh": "new_jwt_token" }`

### 3. Logout
- **POST** `/api/logout/`
- **Auth:** Required (Bearer token)
- **Response:** `{ "detail": "Successfully logged out" }`

### 4. Register
- **POST** `/api/register/`
- **Body:** `{ "username": "string", "email": "email", "password": "string", "password2": "string" }`
- **Response:** User object with tokens
- **Rate Limit:** 3 registrations/hour

### 5. Current User
- **GET** `/api/me/`
- **Auth:** Required
- **Response:** Current user details

### 6. Update Profile
- **PUT/PATCH** `/api/me/`
- **Auth:** Required
- **Body:** User fields to update

## OTP Authentication

### 7. Request OTP
- **POST** `/api/auth/otp/request/`
- **Body:** `{ "identifier": "email_or_phone", "channel": "email|sms" }`
- **Response:** `{ "message": "OTP sent", "expires_in": 300 }`

### 8. Verify OTP
- **POST** `/api/auth/otp/verify/`
- **Body:** `{ "identifier": "email_or_phone", "otp_code": "123456" }`
- **Response:** `{ "access": "jwt_token", "refresh": "jwt_token" }`

### 9. Resend OTP
- **POST** `/api/auth/otp/resend/`
- **Body:** `{ "identifier": "email_or_phone" }`
- **Response:** `{ "message": "OTP resent", "expires_in": 300 }`

## Social Authentication

### 10. Social Login
- **POST** `/api/auth/social/login/`
- **Body:** `{ "provider": "google|apple", "id_token": "string" }`
- **Response:** `{ "access": "jwt_token", "refresh": "jwt_token", "user": {...} }`

### 11. Link Social Account
- **POST** `/api/auth/social/link/`
- **Auth:** Required
- **Body:** `{ "provider": "google|apple", "id_token": "string" }`
- **Response:** `{ "message": "Account linked successfully" }`

### 12. Unlink Social Account
- **POST** `/api/auth/social/unlink/`
- **Auth:** Required
- **Body:** `{ "provider": "google|apple" }`
- **Response:** `{ "message": "Account unlinked successfully" }`

## Dynamic Forms

### 13. Get Form Schema
- **GET** `/api/forms/schema/{form_type}/`
- **Params:** `form_type` = login|register|reset_password|profile
- **Response:** JSON schema for form

### 14. Validate Form
- **POST** `/api/forms/validate/`
- **Body:** `{ "form_type": "string", "data": {...} }`
- **Response:** `{ "valid": true/false, "errors": {...} }`

### 15. Submit Form
- **POST** `/api/forms/submit/`
- **Body:** `{ "form_type": "string", "data": {...} }`
- **Response:** Form-specific response

## Version Management

### 16. Check Version
- **POST** `/api/channels/version/check/`
- **Body:** `{ "platform": "ios|android", "version": "1.0.0" }`
- **Response:** 
```json
{
  "update_required": false,
  "update_available": true,
  "latest_version": "1.2.0",
  "download_url": "https://...",
  "features": { "dark_mode": true, "social_login": false }
}
```

### 17. Get Latest Version
- **GET** `/api/channels/version/latest/?platform=ios`
- **Response:** Latest version info for platform

### 18. Get Supported Versions
- **GET** `/api/channels/version/supported/?platform=ios`
- **Response:** List of all supported versions

### 19. Get Feature Flags
- **GET** `/api/channels/features/?platform=ios&version=1.0.0`
- **Auth:** Required
- **Response:** `{ "dark_mode": true, "social_login": false, ... }`

## Channel Management

### 20. List Channels
- **GET** `/api/channels/`
- **Auth:** Required
- **Response:** Paginated list of channels

### 21. Get Channel
- **GET** `/api/channels/{id}/`
- **Auth:** Required
- **Response:** Channel details

### 22. Create Channel
- **POST** `/api/channels/`
- **Auth:** Required (Admin)
- **Body:** Channel data
- **Response:** Created channel

### 23. Update Channel
- **PUT/PATCH** `/api/channels/{id}/`
- **Auth:** Required (Admin)
- **Body:** Channel updates
- **Response:** Updated channel

### 24. Delete Channel
- **DELETE** `/api/channels/{id}/`
- **Auth:** Required (Admin)
- **Response:** 204 No Content

## Shorts Endpoints

These endpoints surface recent "shorts" playlists per channel with tenant awareness and optional deterministic ordering.

### 25. List Recent Shorts Playlists
- **GET** `/api/channels/shorts/playlists/`
- **Auth:** Required
- **Headers:**
  - `X-Tenant-Id: ontime`
  - `Authorization: Bearer <ACCESS>`
- **Query Params:**
  - `updated_since` (ISO8601, optional) — default: now - 30 days
  - `days` (int, optional) — alternative to updated_since; default 30
  - `limit` (int, optional) — default 100
  - `offset` (int, optional) — default 0
  - `per_channel_limit` (int, optional) — default 5
  - `channel` (slug, optional) — filter by channel slug
- **Notes:**
  - Playlists are tenant-filtered and active-only.
  - Recency is based on latest video publish time, falling back to `last_synced_at`.
- **Response:**
  - Paginated payload with `results` of PlaylistSerializer fields.
- **Example:**
```bash
curl -sS "http://localhost:8000/api/channels/shorts/playlists/?limit=50&per_channel_limit=5&days=30" \
  -H "Authorization: Bearer $ACCESS" \
  -H "X-Tenant-Id: ontime"
```

### 26. Get Shorts Feed (Deterministic Shuffle)
- **GET** `/api/channels/shorts/feed/`
- **Auth:** Required
- **Headers:**
  - `X-Tenant-Id: ontime`
  - `Authorization: Bearer <ACCESS>`
  - `X-Device-Id` (optional) — used as seed source if `seed` not provided
- **Query Params:**
  - `updated_since` (ISO8601, optional) — default: now - 30 days
  - `days` (int, optional) — alternative to updated_since; default 30
  - `limit` (int, optional) — default 100
  - `per_channel_limit` (int, optional) — default 5
  - `channel` (slug, optional)
  - `seed` (string, optional) — overrides deterministic seed
  - `recent_bias_count` (int, optional) — number of top recent items to keep before shuffling remainder; default 20
- **Response:**
  - `{ count, results: [{ channel, playlist_id, title, updated_at, items_count }], seed_source }`
- **Example (seeded):**
```bash
curl -sS "http://localhost:8000/api/channels/shorts/feed/?limit=50&per_channel_limit=5&days=30&seed=test-seed" \
  -H "Authorization: Bearer $ACCESS" \
  -H "X-Tenant-Id: ontime"
```

## Admin Endpoints

### 25. Admin Only
- **GET** `/api/admin-only/`
- **Auth:** Required (Admin)
- **Response:** Admin-specific data

### 26. List Users
- **GET** `/api/users/`
- **Auth:** Required (Permission-based)
- **Response:** Paginated user list

## Session Management

### 27. List Sessions
- **GET** `/api/sessions/`
- **Auth:** Required
- **Response:** List of user's active sessions

### 28. Revoke Session
- **DELETE** `/api/sessions/{session_id}/`
- **Auth:** Required
- **Response:** `{ "message": "Session revoked" }`

### 29. Revoke All Sessions
- **POST** `/api/sessions/revoke-all/`
- **Auth:** Required
- **Response:** `{ "message": "All sessions revoked" }`

## Security Headers Required

All requests must include:
- `X-Tenant-Id`: Tenant identifier (e.g., "default", "ontime")
- `Authorization`: Bearer token for authenticated endpoints
- `Content-Type`: application/json for POST/PUT/PATCH requests

## Rate Limits

- Anonymous: 20 requests/hour
- Authenticated: 1000 requests/hour
- Login: 5 attempts/minute
- Registration: 3 attempts/hour
- OTP Request: 3 attempts/10 minutes

## Error Response Format

```json
{
  "error": "Error message",
  "detail": "Detailed error description",
  "code": "ERROR_CODE"
}
```

## Pagination Format

```json
{
  "count": 100,
  "next": "http://api/endpoint/?page=2",
  "previous": null,
  "results": [...]
}
```

## Testing

All endpoints can be tested via Swagger UI:
- http://localhost:8000/swagger/

Or ReDoc:
- http://localhost:8000/redoc/
