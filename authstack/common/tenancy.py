from __future__ import annotations

from typing import Optional
import logging
from django.conf import settings
from django.http import JsonResponse
from django.utils.deprecation import MiddlewareMixin

from tenants.models import Tenant, TenantDomain

logger = logging.getLogger(__name__)


class AuthorizationHeaderNormalizerMiddleware(MiddlewareMixin):
    """
    Dev-only helper: if Swagger UI (or any client) sends a raw JWT without the
    'Bearer ' prefix in the Authorization header, normalize it so DRF SimpleJWT
    can authenticate it. Only active when settings.DEBUG is True.
    """

    def process_request(self, request):
        # Only for /api/* in DEBUG; do nothing in production
        if not getattr(settings, "DEBUG", False):
            return None
        if not (request.path or "").startswith("/api/"):
            return None

        header = request.META.get("HTTP_AUTHORIZATION")
        if not header:
            return None

        # If it already has the Bearer prefix, leave it
        if header.startswith("Bearer "):
            return None

        # If it's a JWT without the prefix, add it
        # Heuristic: dot-separated segments typical of JWTs
        if header.count(".") >= 2:
            request.META["HTTP_AUTHORIZATION"] = f"Bearer {header}"
            # Mirror to request.headers for Django's case-insensitive mapping environments
            try:
                request.headers["Authorization"] = request.META["HTTP_AUTHORIZATION"]
            except Exception:
                pass
            logger.debug("Normalized Authorization header by adding 'Bearer ' prefix for /api/* request")
        return None


class TenantResolverMiddleware(MiddlewareMixin):
    """
    Resolve request.tenant from Host (portal) or X-Tenant-Id header (mobile).
    If path starts with /api/ and no tenant could be resolved, return 400.
    """

    HEADER_NAME = "X-Tenant-Id"

    def process_request(self, request):
        # For API requests, log presence of Authorization and X-Tenant-Id headers (DEBUG only)
        if logger.isEnabledFor(logging.DEBUG) and request.path.startswith("/api/"):
            auth_header = request.headers.get("Authorization") or request.META.get("HTTP_AUTHORIZATION")
            tenant_header = request.headers.get(self.HEADER_NAME) or request.META.get(
                f"HTTP_{self.HEADER_NAME.replace('-', '_').upper()}"
            )

            def _mask_token(tok: str) -> str:
                try:
                    if not tok:
                        return "<none>"
                    if tok.startswith("Bearer "):
                        t = tok[len("Bearer "):]
                    else:
                        t = tok
                    if len(t) <= 12:
                        return f"***{t[-4:]}"
                    return f"{t[:6]}...{t[-4:]} (len={len(t)})"
                except Exception:
                    return "<unreadable>"

            masked = _mask_token(auth_header)
            logger.debug("Auth header present: %s; X-Tenant-Id: %s", masked, tenant_header or "<none>")

        tenant = self._resolve_tenant(request)
        if tenant is None and request.path.startswith("/api/"):
            # Emit a concise debug log to help diagnose why tenant was not resolved
            header_val = request.headers.get(self.HEADER_NAME) or request.META.get(
                f"HTTP_{self.HEADER_NAME.replace('-', '_').upper()}"
            )
            host_only = (request.get_host() or "").split(":")[0]
            logger.debug(
                "Tenant resolution failed: path=%s header[%s]=%s host=%s",
                request.path,
                self.HEADER_NAME,
                header_val,
                host_only,
            )
            return JsonResponse({"detail": "Unknown tenant"}, status=400)
        request.tenant = tenant

    def _resolve_tenant(self, request) -> Optional[Tenant]:
        # 1) Mobile header takes precedence if present
        header_tenant = request.headers.get(self.HEADER_NAME) or request.META.get(
            f"HTTP_{self.HEADER_NAME.replace('-', '_').upper()}"
        )
        if header_tenant:
            tenant = Tenant.objects.filter(slug=header_tenant, active=True).first()
            logger.debug(
                "Tenant resolution via header: %s -> %s",
                header_tenant,
                getattr(tenant, "slug", None),
            )
            return tenant

        # 2) Portal host: use subdomain part (left-most label)
        host = request.get_host().split(":")[0]
        # Ignore localhost without subdomain
        if host and "." in host:
            subdomain = host.split(".")[0]
            # Optionally ignore common prefixes
            if subdomain and subdomain.lower() not in {"www"}:
                # Try direct slug match first
                t = Tenant.objects.filter(slug=subdomain, active=True).first()
                if t:
                    logger.debug("Tenant resolution via subdomain: host=%s subdomain=%s -> %s", host, subdomain, t.slug)
                    return t
                # Then via explicit domain mapping table
                dom = TenantDomain.objects.filter(domain=host).select_related("tenant").first()
                if dom and dom.tenant.active:
                    logger.debug("Tenant resolution via domain mapping: host=%s -> %s", host, dom.tenant.slug)
                    return dom.tenant
        else:
            logger.debug("Tenant resolution skipped host branch (no dot in host): host=%s", host)
        return None
