# App Version Gate — Bullet Spec (Flutter + Django/DRF)

## What this is called
- App **Version Gate** / **Version Enforcement**
- **Force Update** (hard block) + **Soft Update** (optional prompt)
- Also known as **Client Min-Version Policy** / **Kill Switch**

## Goals
- Ensure users run a **supported** app version at all times.
- Allow backend to **force-stop** old clients (security/compatibility).
- Provide **soft nudge** for non-critical updates.
- Keep UX fast; fail-open when backend is unreachable (configurable).

## Definitions
- **platform**: `android` | `ios`
- **current**: client app version (e.g., `1.2.3`)
- **latest**: newest version in store (e.g., `1.3.0`)
- **min_supported**: lowest version allowed to use APIs (e.g., `1.2.0`)
- **force update**: `current < min_supported`
- **soft update**: `min_supported ≤ current < latest`

## Client Methods (Flutter)
- **Startup Gate**: Check `/app/version` before showing the main app.
- **Global Interceptor**: Send `X-App-Version` + `X-App-Platform` headers on **every** API call; handle **HTTP 426** (Upgrade Required).
- **Background Refresh**: Re-check version on app resume / every N hours.
- **Store Deep Links**: Use `market://` (Android) / `itms-apps://` (iOS) with web fallbacks.
- **Copy**: Short, localized; show *Update now* / *Later* (soft), *Update required* (force).

## Flutter Project Structure (suggested)
- `lib/core/env/`  
  - `env.dart` (base), `env_dev.dart`, `env_prod.dart` (API base URLs, package IDs)
- `lib/core/network/`  
  - `http_client.dart` (adds JWT + version headers)  
  - `interceptors/version_interceptor.dart` (handles 426)
- `lib/core/services/`  
  - `version_service.dart` (GET `/app/version`, compare semver)
- `lib/core/widgets/`  
  - `version_gate.dart` (startup blocker + dialogs)
- `lib/app/`  
  - `app.dart` (MaterialApp root; wraps home with `VersionGate`)
- `lib/features/auth/` (existing JWT views)
- `lib/features/update/`  
  - `update_dialog.dart` (reusable soft/force modals)
- `lib/l10n/` (strings, Amharic + English)
- `lib/utils/`  
  - `semver.dart` (version compare: major.minor.patch)

## Flutter Lifecycle Integration
- **App start**: `VersionGate` calls backend; force = full-screen gate; soft = dialog.
- **On resume**: re-check if last check > N hours.
- **Every request**: headers `X-App-Version` & `X-App-Platform`.
- **On 426**: show force gate immediately (even mid-session).

## UX (copy + behavior)
- **Soft**: “Update available — New features & fixes.” Buttons: **Update**, **Later**.
- **Force**: “Update required — Your version is no longer supported.” Button: **Update now** only.
- **Offline**: allow entry (configurable), and re-check later; cache last verdict.

## Network & Offline Policy
- Default **fail‑open** if `/app/version` fails (no blocking without a signal).  
- Cache last successful payload for 24h; compare locally.
- Timeouts: 3–5s with 1 retry.

## JWT & API Enforcement (server-backed)
- Add headers on **all** authenticated requests:  
  - `X-App-Platform: android|ios`  
  - `X-App-Version: 1.2.3`
- Backend permission/middleware checks: if `current < min_supported`, return **426 Upgrade Required** with JSON body.
- Exempt endpoints: `/app/version`, `/auth/*` (login/refresh/register), health checks.

## Backend Endpoint (contract)
- **Method**: `GET /app/version?platform=android|ios`
- **Request headers** (optional but useful): `X-App-Version`, `X-App-Platform`
- **Response 200 JSON**:
  ```json
  {
    "platform": "android",
    "latest": "1.3.0",
    "min_supported": "1.2.0",
    "store_url": "market://details?id=com.ybs.ontime",
    "notes": "Bug fixes; improved live playback"
  }
  ```
- **Force block response (any protected API)**:
  - **426 Upgrade Required**
  - Body:
    ```json
    {"code": "APP_UPDATE_REQUIRED", "min_supported": "1.2.0"}
    ```

## Backend Implementation Notes (Django/DRF)
- Config in settings:
  - `APP_VERSION["android"|"ios"] = { latest, min_supported, store_url, notes }`
- Views:
  - `AppVersionView (AllowAny)` returns config.
- Middleware/Permission:
  - `EnforceMinVersion` compares `X-App-Version` with `min_supported` and raises 426.
- Routing:
  - `GET /app/version` (public)  
  - Apply `EnforceMinVersion` to protected routes (after authentication).
- Caching:
  - Cache `/app/version` for 30–60s (CDN or Django cache) to reduce load.
- Admin ops:
  - Only authorized staff can bump versions (admin UI / env vars).

## Localhost / Dev Setup
- Use `http://127.0.0.1:8000/app/version` during development.
- iOS ATS: allow local HTTP for dev (or use `https://` with a dev cert).
- Flutter builds: keep **package name/App ID** stable to test store links; for dev, store_url can be any URL.
- Seed data: set `latest = min_supported` initially to avoid accidental force locks.

## Security / Abuse Controls
- Validate headers; don’t trust client decisions.
- Limit `/app/version` read with basic rate limiting (not strict).
- Log when 426 is returned (user agent, version, platform).
- Keep comparison strictly **major.minor.patch** numeric; ignore labels.

## Telemetry
- Count: soft shown, soft accepted, soft dismissed; force shown; store link opens.
- Track 426 frequency by version to measure rollout effect.
- Dashboard: current version mix (from headers).

## Release Checklist
- Bump `latest` once store release is fully live.
- Bump `min_supported` only after staged % of users on new version.
- Verify store URLs & fallbacks.
- Verify dialogs in both languages (Amharic/English).
- QA on slow network + offline.
- Add changelog to `notes` (short).

## Test Matrix
- `current < min_supported` → force gate, 426 on protected APIs.
- `current == min_supported` → allowed; no soft prompt.
- `min_supported < current < latest` → soft prompt once per session.
- `current >= latest` → no prompt.
- API down / timeout → fail‑open (configurable), retry later.
- 426 mid-session → show force gate immediately; navigating back is blocked.

## Future Enhancements
- Remote percentages (gradual min_supported increase by cohort).
- Country‑specific store URLs.
- In‑app incremental updates (Android App Bundles) where applicable.
- Admin UI to edit version config + broadcast release notes.
