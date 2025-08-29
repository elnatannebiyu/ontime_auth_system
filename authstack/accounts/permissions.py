from typing import Iterable
from rest_framework.permissions import BasePermission, SAFE_METHODS
from .models import Membership

class HasAnyRole(BasePermission):
    """Allow only users who have at least one of the required roles (Django groups)."""
    required_roles: Iterable[str] = ()

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        if not self.required_roles:
            return True
        user_groups = set(request.user.groups.values_list("name", flat=True))
        return bool(user_groups.intersection(set(self.required_roles)))

class DjangoPermissionRequired(BasePermission):
    """Check a specific Django permission codename, e.g. 'accounts.change_user'."""
    required_perm: str | None = None

    def has_permission(self, request, view):
        if not request.user or not request.user.is_authenticated:
            return False
        if not self.required_perm:
            return True
        return request.user.has_perm(self.required_perm)

class ReadOnlyOrPerm(DjangoPermissionRequired):
    """Allow read-only to authenticated; require perm for write."""
    def has_permission(self, request, view):
        if request.method in SAFE_METHODS:
            return bool(request.user and request.user.is_authenticated)
        return super().has_permission(request, view)


class IsTenantMember(BasePermission):
    """Require that the authenticated user is a member of request.tenant."""

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        tenant = getattr(request, "tenant", None)
        if not user or not user.is_authenticated or not tenant:
            return False
        return Membership.objects.filter(user=user, tenant=tenant).exists()


class TenantMatchesToken(BasePermission):
    """Access token must include tenant_id matching request.tenant.slug.

    We only trust server-side resolution (request.tenant) + token claim agreement.
    """

    def has_permission(self, request, view):
        user = getattr(request, "user", None)
        tenant = getattr(request, "tenant", None)
        if not user or not user.is_authenticated or not tenant:
            return False
        claim_tenant = getattr(request.auth, "payload", {}).get("tenant_id") if hasattr(request, "auth") else None
        return claim_tenant == getattr(tenant, "slug", None)
