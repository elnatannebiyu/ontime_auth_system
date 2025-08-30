# Account Creation Request Payload — Recommended Standard (Mobile Apps)

## Purpose
- Define **standard metadata** a client should send when **creating an account**.
- Keep PII **minimal** at sign‑up; collect extras during onboarding.
- Use **TLS**, server‑side hashing, and clear consent capture.

---

## Endpoint (example)
- **POST** `/api/v1/auth/register`
- **Content‑Type**: `application/json`
- **Idempotency-Key** (header, optional but recommended): prevents duplicate signups on retries.

---

## Core Identity (choose one primary)
- **Email** *(RFC 5322)* **OR** **Phone** *(E.164, e.g., `+2519XXXXXXXX`)*
- **Authentication**:
  - `password` *(min 8–12, server hashes with **Argon2id** or **bcrypt**)* **OR**
  - `otp_code` *(if phone/email OTP)* **OR**
  - `oauth_provider` + `oauth_token` *(Google/Apple, etc.)*

---

## Recommended Request Fields (client → server)
- **identity**
  - `email` *(string, optional)*
  - `phone_e164` *(string, optional)*
  - `username` *(string, optional, unique; slug rules)*
  - `display_name` *(string, optional)*
- **auth**
  - `password` *(string, optional)*
  - `otp_code` *(string, optional, length 6)*
  - `oauth_provider` *(enum: `google`, `apple`, ...)*
  - `oauth_access_token`/`id_token` *(string, optional)*
- **consent & policy**
  - `terms_accepted` *(bool, required)*
  - `privacy_accepted` *(bool, required)*
  - `age_confirmed` *(bool, required if COPPA/age‑gated content)*
  - `marketing_opt_in` *(bool, optional)*
- **locale**
  - `country` *(ISO 3166‑1 alpha‑2, e.g., `ET`)*
  - `locale` *(BCP‑47, e.g., `am-ET` or `en-US`)*
  - `timezone` *(IANA, e.g., `Africa/Addis_Ababa`)*
- **app / device context**
  - `platform` *(enum: `android`, `ios`)*
  - `app_version` *(semver: `major.minor.patch`)*
  - `build_number` *(string/int)*
  - `device_model` *(string, optional)*
  - `os_version` *(string, optional)*
  - `install_id` *(UUID v4, app‑scoped random ID)*
  - `push_token` *(string, optional)*
  - `referral_code` *(string, optional)*
  - `attribution` *(object, optional; campaign/channel)*
- **security / anti‑abuse**
  - `captcha_token` *(string, optional; reCAPTCHA/Arkose)*
  - `device_integrity` *(object, optional; Play Integrity / DeviceCheck)*
  - (server derives `ip_address`, `user_agent` from request)
- **profile (collect later if not needed)**
  - `dob` *(ISO 8601 date, optional; only if age required)*
  - `gender` *(string, optional)*
  - `avatar_url` *(string, optional)*

> Keep email/phone **one primary** on creation; link the other later.

---

## Example JSON — Email + Password
```json
{
  "email": "user@example.com",
  "password": "S3curePass!",
  "display_name": "Zion",
  "terms_accepted": true,
  "privacy_accepted": true,
  "marketing_opt_in": false,
  "country": "ET",
  "locale": "am-ET",
  "timezone": "Africa/Addis_Ababa",
  "platform": "android",
  "app_version": "1.2.3",
  "build_number": "1203",
  "install_id": "9f4c1d34-5d7d-4b38-9a2b-23cd2a3f3a10",
  "push_token": "fcm-token-abc",
  "referral_code": "ABBAY2025"
}
```

## Example JSON — Phone + OTP
```json
{
  "phone_e164": "+251911234567",
  "otp_code": "482913",
  "display_name": "Zion",
  "terms_accepted": true,
  "privacy_accepted": true,
  "country": "ET",
  "locale": "am-ET",
  "timezone": "Africa/Addis_Ababa",
  "platform": "android",
  "app_version": "1.2.3",
  "install_id": "9f4c1d34-5d7d-4b38-9a2b-23cd2a3f3a10"
}
```

## Example JSON — Social (Google)
```json
{
  "oauth_provider": "google",
  "id_token": "eyJhbGciOiJSUzI1NiIs...",
  "display_name": "Zion",
  "terms_accepted": true,
  "privacy_accepted": true,
  "platform": "ios",
  "app_version": "1.2.3",
  "install_id": "b9ed2a34-1baf-4c9a-b3a2-7a8f1f9e12de"
}
```

---

## Server Response (recommended)
- **201 Created**
  - `id` *(UUID v4)*
  - `email` / `phone_e164`
  - `email_verified` / `phone_verified` *(bool)*
  - `access_token` *(JWT, short‑lived)*
  - `refresh_token` *(JWT/opaque, long‑lived)*
  - `expires_in` *(seconds)*
  - `requires_verification` *(bool; if email/phone confirm pending)*
  - `created_at` *(ISO 8601)*
  - `profile` *(basic profile object)*

- **409 Conflict** if identity already exists (include hint for sign‑in or account linking).

---

## Validation Standards
- **Email**: RFC 5322; normalize case to lower for lookup.
- **Phone**: E.164 only; server validates and normalizes.
- **Password**: min length 8–12; check breach list (k‑Anon Pwned) server‑side.
- **Username**: lowercase slug `[a-z0-9_]{3,20}`; reserve keywords.
- **Country**: ISO 3166‑1 alpha‑2; **Locale**: BCP‑47; **Timezone**: IANA.
- **UUIDs**: v4; **Dates**: ISO 8601; **Version**: semver `x.y.z`.

---

## Security & Compliance
- **Never store plaintext passwords**; hash with **Argon2id** (or bcrypt/12+).
- Require **TLS**; reject insecure origins in prod.
- Throttle signup & OTP endpoints; rate‑limit per IP + install_id.
- Log consents with `consent_ts` (server clock).
- Respect **GDPR/CCPA**: purpose limitation, allow deletion & export.
- Avoid persistent hardware IDs; use app‑scoped **install_id** instead.

---

## Backend Notes
- Create accounts as **unverified** until email/phone verified.
- Enforce **unique** per primary identifier (email OR phone).
- Support later **linking** (phone ↔ email ↔ social).
- Populate server‑side audit fields: `created_at`, `updated_at`, `last_login_ip`.
- Return **426 Upgrade Required** when `X-App-Version` is below `min_supported` (from your Version Gate policy).

---

## Minimal vs Standard
- **Minimal**: { email OR phone, password/otp, terms_accepted, platform, app_version }
- **Standard (recommended)**: Minimal **+** locale, timezone, install_id, consent flags, marketing_opt_in, referral_code, device context, and anti‑abuse token.

---

## Error Model (examples)
- `400 VALIDATION_ERROR` — field errors map
- `401 INVALID_OTP` — wrong or expired code
- `409 ALREADY_EXISTS` — email/phone taken
- `429 RATE_LIMITED` — too many attempts
- `500 SERVER_ERROR` — generic

---

## Tracking & Analytics
- Track **signup method** (email/phone/social), region, and conversion.
- Attribute via `referral_code`/`attribution` if available.
- Monitor verification completion rate (email/phone).

