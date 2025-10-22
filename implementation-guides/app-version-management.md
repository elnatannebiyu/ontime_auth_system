# App Version Management Manual

This guide explains how to manage app versions, enforce updates, and validate behavior via the Version Gate. It applies to the `channels` app in the backend and the Flutter client integration.

## Where things live

- **Models/Admin**: `onchannels/version_models.py` (`AppVersion`, `FeatureFlag`), registered in `onchannels/admin.py`.
- **Service logic**: `onchannels/version_service.py` (`VersionCheckService.check_version()`).
- **API endpoints**: `onchannels/urls.py`
  - `POST /api/channels/version/check/`
  - `GET /api/channels/version/latest/`
  - `GET /api/channels/version/supported/`
  - `GET /api/channels/features/`
- **Client Version Gate**: `Ontime_ethiopia_flutterapp/lib/core/version/version_gate.dart` calls `POST /api/channels/version/check/`.

## Admin: Creating and Maintaining Versions

- **Path**: Django Admin → `channels → App versions` (model `AppVersion`).
- **New version row fields**:
  - **platform**: `ios` | `android` | `web`
  - **version**: Semantic string (e.g., `1.0.1`)
  - **build_number**: iOS build number (int)
  - **version_code**: Android version code (int)
  - **status**: `active` | `deprecated` | `unsupported` | `blocked`
  - **update_type**: `optional` | `required` | `forced`
  - **min_supported_version**: Smallest version allowed without blocking
  - **update_title**, **update_message**, **force_update_message`
  - **ios_store_url**, **android_store_url`
  - **features** (JSON), **changelog**
- **Best practice**:
  - Start with `update_type=optional` to show non-blocking prompts.
  - To invalidate an old build, set on the latest row:
    - `min_supported_version` to the new version (e.g., `1.0.1`) and
    - `update_type=forced` (or set the old row’s `status=blocked/unsupported`).
  - Fill store URLs to enable deep-linking from prompts (client can open store).

## API Usage (tenant-aware)

Include the tenant header `X-Tenant-Id: ontime` in all requests.

- **Check the latest version**
```bash
BASE=http://localhost:8000
TENANT=ontime
curl -s "$BASE/api/channels/version/latest/?platform=ios" \
  -H "X-Tenant-Id: $TENANT" | jq .
```

- **Check app version (what the client calls on startup)**
```bash
curl -s -X POST "$BASE/api/channels/version/check/" \
  -H "X-Tenant-Id: $TENANT" \
  -H "Content-Type: application/json" \
  -d '{"platform":"ios","version":"1.0.0","build_number":1}' | jq .
```

- Response shape (high-level):
  - `update_required`: boolean
  - `update_available`: boolean
  - `update_type`: `optional | required | forced`
  - `message`: string
  - `store_url`: string (if configured)
  - `checked_at`: timestamp
  - Optional `features` if authenticated

## How update enforcement works

- **Optional update (prompt only)**
  - Latest `update_type=optional` and no `min_supported_version`.
  - Apps below `latest` get a non-blocking prompt.

- **Forced update (block)**
  - If the current version is:
    - Below `min_supported_version` on the latest row; or
    - Its own `AppVersion.status` is `blocked` or `unsupported`.
  - API returns `update_required=true`, `update_type=forced`.
  - Client shows a blocking dialog (wired in `VersionGate`).

- **Required update**
  - Similar to forced but treated as blocking in our client.

## Client integration

- **Startup behavior**: `VersionGate.checkAndPrompt()` is called after app’s first frame in `lib/main.dart`.
- **UI**:
  - `forced/required`: Blocking dialog with an Update button.
  - `optional`: SnackBar with Update action.
- To open the store URL directly, wire `url_launcher` (optional enhancement).

## Release workflows

- **Soft rollout**
  - Create new version row (e.g., Android `1.0.1`) with `update_type=optional`.
  - Users see a prompt but aren’t blocked.

- **Force update**
  - Set `min_supported_version` on the latest to `1.0.1`.
  - Optionally set old versions `status=unsupported` or `blocked`.
  - Users below `1.0.1` are blocked and guided to store.

## Validation checklist

- **Create version rows** for `ios` and `android`.
- **Validate optional prompt**:
  - Set latest `update_type=optional`, no `min_supported_version`.
  - Client should show a non-blocking prompt.
- **Validate forced update**:
  - Set `min_supported_version` higher than the app’s current version (and `update_type=forced`).
  - Client should show a blocking dialog.
- **API sanity**:
  - `GET /api/channels/version/latest/?platform=ios`
  - `POST /api/channels/version/check/`
  - Both with `X-Tenant-Id: ontime`.

## Troubleshooting

- **“Unknown tenant”**: Add `-H "X-Tenant-Id: ontime"` to requests.
- **“No version found”**: Create an `AppVersion` row for that platform in Admin.
- **Client doesn’t show prompt**:
  - Ensure the endpoint returns `update_available=true` or `update_required=true`.
  - Ensure your device app version is below `latest` or below `min_supported_version`.
  - Confirm the client calls `VersionGate.checkAndPrompt()`.
- **Store URL not opening**:
  - Ensure `ios_store_url` / `android_store_url` is set on the latest row.
  - Add `url_launcher` integration if desired.

## Example: Deprecate Android 1.0.0 when releasing 1.0.1

- Admin → Add/Update Android row:
  - `platform=android`, `version=1.0.1`, `version_code=2`
  - `status=active`, `update_type=forced`
  - `min_supported_version=1.0.1`
  - `android_store_url=https://play.google.com/store/apps/details?id=com.example.app`
- Apps on 1.0.0 now receive a forced update response and the client shows a blocking dialog.
