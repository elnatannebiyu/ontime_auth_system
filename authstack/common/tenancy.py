from __future__ import annotations

from typing import Optional
from django.http import JsonResponse
from django.utils.deprecation import MiddlewareMixin

from tenants.models import Tenant, TenantDomain


class TenantResolverMiddleware(MiddlewareMixin):
    """
    Resolve request.tenant from Host (portal) or X-Tenant-Id header (mobile).
    If path starts with /api/ and no tenant could be resolved, return 400.
    """

    HEADER_NAME = "X-Tenant-Id"

    def process_request(self, request):
        tenant = self._resolve_tenant(request)
        if tenant is None and request.path.startswith("/api/"):
            return JsonResponse({"detail": "Unknown tenant"}, status=400)
        request.tenant = tenant

    def _resolve_tenant(self, request) -> Optional[Tenant]:
        # 1) Mobile header takes precedence if present
        header_tenant = request.headers.get(self.HEADER_NAME) or request.META.get(
            f"HTTP_{self.HEADER_NAME.replace('-', '_').upper()}"
        )
        if header_tenant:
            return Tenant.objects.filter(slug=header_tenant, active=True).first()

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
                    return t
                # Then via explicit domain mapping table
                dom = TenantDomain.objects.filter(domain=host).select_related("tenant").first()
                if dom and dom.tenant.active:
                    return dom.tenant
        return None
