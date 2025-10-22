from __future__ import annotations
from typing import Optional
from django.http import JsonResponse, HttpRequest
from django.utils.deprecation import MiddlewareMixin
from django.urls import resolve

try:
    from onchannels.version_models import AppVersion, VersionStatus
except Exception:  # pragma: no cover
    AppVersion = None  # type: ignore
    VersionStatus = None  # type: ignore


# Exact paths that remain allowed even when outdated (logout only)
SAFE_PATHS_EXACT = (
    "/api/logout/",
)

# Prefixes allowed (version endpoints only)
SAFE_PATH_PREFIXES = (
    "/api/channels/version/",
)

SAFE_NAMESPACES = (
    "admin",
    "static",
)


def _parse_version_tuple(v: str) -> tuple:
    parts = (v or "0").split(".")
    out = []
    for p in parts:
        try:
            out.append(int(p))
        except Exception:
            out.append(0)
    while len(out) < 3:
        out.append(0)
    return tuple(out[:3])


class AppVersionEnforceMiddleware(MiddlewareMixin):
    """Return HTTP 426 Upgrade Required when app version is below minimum.

    Expects headers injected by the mobile client:
      - X-Device-Platform: ios|android|web
      - X-App-Version: semantic version string e.g. 1.0.0

    Safe-list version and auth endpoints to avoid dead-ends.
    """

    def process_request(self, request: HttpRequest):
        # Skip admin/static and safe prefixes
        path = request.path or ""
        if path in SAFE_PATHS_EXACT:
            return None
        if any(path.startswith(p) for p in SAFE_PATH_PREFIXES):
            return None
        try:
            match = resolve(path)
            if match and match.namespace in SAFE_NAMESPACES:
                return None
        except Exception:
            pass

        # Extract platform/version from headers
        platform = request.headers.get("X-Device-Platform", "").lower().strip()
        version = request.headers.get("X-App-Version", "").strip()
        if not platform or not version:
            # If we cannot determine platform/version, allow through
            return None

        if AppVersion is None:
            return None

        # Latest active for platform
        latest: Optional[AppVersion] = (
            AppVersion.objects.filter(platform=platform, status=VersionStatus.ACTIVE.value)
            .order_by("-released_at")
            .first()
        )
        if not latest:
            return None

        # If there is a row for current version and it's blocked/unsupported -> force update
        current = AppVersion.objects.filter(platform=platform, version=version).first()
        if current and current.status in {VersionStatus.BLOCKED.value, VersionStatus.UNSUPPORTED.value}:
            return self._reject(latest)

        # If min_supported_version is set on latest, enforce it
        msv = (latest.min_supported_version or "").strip()
        if msv:
            if _parse_version_tuple(version) < _parse_version_tuple(msv):
                return self._reject(latest)

        return None

    def _reject(self, latest: AppVersion):
        payload = {
            "code": "APP_UPDATE_REQUIRED",
            "update_required": True,
            "update_type": "forced",
            "title": getattr(latest, "update_title", None) or "Update Required",
            "message": getattr(latest, "force_update_message", None)
            or "This version is no longer supported. Please update to continue.",
            "platform": latest.platform,
            "latest_version": latest.version,
            "min_supported_version": getattr(latest, "min_supported_version", "") or "",
            "store_url": latest.ios_store_url if latest.platform == "ios" else latest.android_store_url,
        }
        # 426 Upgrade Required
        return JsonResponse(payload, status=426)
