# Backend‑Driven Auth Forms — Spec (Login & Register)

## Purpose
- Backend defines **login/register forms**; client renders them dynamically.
- Allows **A/B tests**, **locale-specific** fields, **country rules**, and **security updates** without app releases.
- Works with **JWT** auth and your **Version Gate** (426 policy).

---

## High‑Level Flow
1. Client boots → sends **Version Gate** headers (`X-App-Version`, `X-App-Platform`) on every call.
2. Client requests **form schema**:
   - `GET /api/v1/auth/forms?name=login`
   - `GET /api/v1/auth/forms?name=register`
3. Server returns **schema JSON** (+ ETag/Cache headers) describing fields, validation, layout, actions.
4. Client renders form → user submits → server validates → returns JWT / next step (OTP).
5. Server can **change fields**/rules centrally; clients update on next fetch or ETag change.

---

## Required Endpoints
- **Fetch form schema**
  - `GET /api/v1/auth/forms?name=login|register[&locale=am-ET&country=ET&variant=A]`
  - Headers (recommended):  
    - `Accept-Language: am-ET` (or query `locale`)  
    - `X-App-Version: 1.2.3`  
    - `X-App-Platform: android|ios`
  - Responses: `200 OK`, with `ETag` and `Cache-Control: public, max-age=300`
  - Error if unknown form: `404 FORM_NOT_FOUND`
- **Submit login**
  - `POST /api/v1/auth/login` → `200 OK` with `access_token`, `refresh_token`, `profile`, or `401` with field errors.
- **Submit register**
  - `POST /api/v1/auth/register` → `201 Created` with tokens (or `requires_verification: true`).
- **OTP**
  - `POST /api/v1/auth/otp/send` (email/phone)  
  - `POST /api/v1/auth/otp/verify`
- **Social providers**
  - `GET /api/v1/auth/providers` (e.g., `google`, `apple`) for dynamic button rendering.
- **Version**
  - `GET /app/version?platform=android|ios` (AllowAny). Protected APIs enforce 426 via middleware.

---

## Schema Object — Overview
- **Top‑level keys**: `schema_version`, `form`, `meta`, `layout`, `fields[]`, `actions[]`, `i18n`, `validation`.
- **Rules**:
  - Server is **source of truth**; client never trusts UI for validation.
  - Use **stable field names** (snake_case); send unknown fields to server unchanged.
  - Backward compatible changes only; bump `schema_version` for breaking changes.

---

## Example — Login Form Schema (JSON)
```json
{
  "schema_version": "2025.08",
  "form": {
    "name": "login",
    "method": "POST",
    "action": "/api/v1/auth/login"
  },
  "meta": {
    "variant": "A",
    "captcha": false,
    "otp_supported": true,
    "min_app_version": "1.2.0"
  },
  "layout": {
    "style": "glass",
    "order": ["identity_group", "password", "remember_me", "divider", "social_buttons", "phone_cta"]
  },
  "fields": [
    {
      "id": "identity_group",
      "type": "group",
      "label": "Identity",
      "children": ["email", "phone_e164"],
      "switch": {"exclusive": true, "default": "email"}
    },
    {
      "name": "email",
      "type": "email",
      "label": "Email",
      "required": true,
      "visible_if": {"field": "identity_group", "value": "email"},
      "autofill": "email",
      "validators": {"format": "email"}
    },
    {
      "name": "phone_e164",
      "type": "phone",
      "label": "Phone",
      "required": true,
      "visible_if": {"field": "identity_group", "value": "phone_e164"},
      "input_mask": "+000 000 000 000",
      "validators": {"format": "e164", "country_default": "ET"}
    },
    {
      "name": "password",
      "type": "password",
      "label": "Password",
      "required": true,
      "validators": {"min_length": 8}
    },
    {
      "name": "remember_me",
      "type": "checkbox",
      "label": "Remember me",
      "default": true
    }
  ],
  "actions": [
    {
      "id": "submit",
      "type": "submit",
      "label": "Sign in",
      "primary": true
    },
    {
      "id": "forgot",
      "type": "link",
      "label": "Forgot password?",
      "href": "/reset/request"
    },
    {
      "id": "phone_login",
      "type": "link",
      "label": "Use phone (OTP)",
      "href": "/otp/start"
    },
    {
      "id": "google",
      "type": "oauth",
      "provider": "google",
      "label": "Continue with Google"
    },
    {
      "id": "apple",
      "type": "oauth",
      "provider": "apple",
      "label": "Continue with Apple"
    }
  ],
  "i18n": {
    "locale": "am-ET",
    "strings": {}
  }
}
```

---

## Example — Register Form Schema (JSON)
```json
{
  "schema_version": "2025.08",
  "form": {
    "name": "register",
    "method": "POST",
    "action": "/api/v1/auth/register"
  },
  "meta": {
    "captcha": true,
    "otp_required": true,
    "age_gate": false,
    "min_app_version": "1.2.0"
  },
  "layout": {
    "style": "glass",
    "order": ["display_name", "email_or_phone", "password", "consents", "submit"]
  },
  "fields": [
    {"name": "display_name", "type": "text", "label": "Display name", "required": false, "max_length": 50},
    {"name": "email", "type": "email", "label": "Email", "required": false},
    {"name": "phone_e164", "type": "phone", "label": "Phone", "required": false, "validators": {"format": "e164", "country_default": "ET"}},
    {
      "name": "password",
      "type": "password",
      "label": "Password",
      "required": true,
      "validators": {"min_length": 8, "zxcvbn_hint": true}
    },
    {"name": "terms_accepted", "type": "checkbox", "label": "I agree to Terms", "required": true},
    {"name": "privacy_accepted", "type": "checkbox", "label": "I agree to Privacy", "required": true}
  ],
  "actions": [{"id": "submit", "type": "submit", "label": "Create account", "primary": true}],
  "validation": {
    "one_of": [["email", "phone_e164"]], 
    "unique": ["email", "phone_e164"]
  }
}
```

---

## Client Rendering Rules (Flutter)
- Map `type` → widgets: `email`, `phone`, `password`, `text`, `checkbox`, `otp`, `oauth`, `group`.
- Honor `required`, `max_length`, `validators` (email format, E.164).
- Implement `visible_if`, `switch.exclusive` (toggle between email/phone).
- Use `layout.order` to arrange controls; ignore unknown fields gracefully.
- Use `i18n.locale` if provided; otherwise `Accept-Language` fallback.
- Cache schema by `ETag`; re-fetch on `304` or when app resumes after N hours.
- Always include headers: `X-App-Version`, `X-App-Platform`, `X-Install-Id`.

---

## Submission Contract
- Submit to `form.action` using `form.method` with a flat JSON body of visible fields.
- Add headers: `Content-Type: application/json`, `X-App-Version`, `X-App-Platform`.
- Server response:
  - **Login**: `200 OK` → `{ access_token, refresh_token, profile, requires_verification? }`
  - **Register**: `201 Created` → same as above; may set `requires_verification: true`.
  - **Next step**: `{ next_step: "otp_verify", sent_to: "+251..." }`.
- Error model:
  ```json
  {
    "code": "VALIDATION_ERROR",
    "message": "Please correct the highlighted fields.",
    "field_errors": {
      "email": "Invalid email format",
      "password": "Too short"
    }
  }
  ```

---

## Version Gate Integration
- If `X-App-Version < min_supported` (server policy), server returns **426 Upgrade Required** to any protected endpoint.
- Form endpoints remain **AllowAny**, but include `meta.min_app_version` so client can gate UI early.

---

## Security
- All validation **re-done server‑side**; client schema is advisory.
- **TLS only**; HSTS in production.
- Throttle: per IP + `X-Install-Id`; add **captcha** gates when abuse detected.
- Passwords hashed (**Argon2id** or **bcrypt**), never logged.
- OTP: rate limit + short TTL; bind to `install_id` to reduce relay abuse.
- Avoid collecting PII you don’t need at sign‑up; add later via onboarding.

---

## Caching & Versioning
- `ETag` + `Cache-Control: max-age=300` for form schemas.
- `schema_version` for compatibility; only additive changes without bump.
- Invalidate cache on admin changes (etag bump).

---

## i18n
- Server returns labels/placeholders for requested `locale`.
- Provide ISO codes: `country` (ET), `locale` (am-ET), `timezone` (Africa/Addis_Ababa).
- Fallback chain: requested → server default → English.

---

## Analytics
- Track: form view, field error counts, submit success, OTP success.
- Dimensions: method (email/phone/social), platform, country, app_version, variant.

---

## Admin & Ops
- Admin UI to edit fields/labels/validators per form, per locale, per country.
- Audit changes with `actor`, `diff`, `timestamp`.
- Rollback previous schema fast (schema history).

---

## Localhost / Dev
- Base URL examples: `http://127.0.0.1:8000/api/v1/auth/forms`.
- Allow HTTP only in dev; iOS ATS exceptions or use self‑signed HTTPS.
- Seed schemas as fixtures; expose `/admin/auth/forms/preview`.

---

## Minimal Client Folder Hints (Flutter, no code)
- `lib/core/forms/schema_provider.dart` (fetch + cache by ETag)
- `lib/core/forms/form_renderer.dart` (map schema → widgets)
- `lib/core/forms/validators.dart` (email, e164, required, minLength)
- `lib/core/forms/widgets/` (TextField, PhoneField, Checkbox, OauthButton, OtpField)
- `lib/core/forms/logic/` (visible_if, exclusive switch, layout order)

---

## Next Steps
- Confirm field lists for your **login** and **register** variants.
- I’ll produce the DRF endpoints: `/auth/forms`, `/auth/login`, `/auth/register`, `/auth/otp/*`, and wire to your JWT + Version Gate.
