from typing import Iterable
from rest_framework.permissions import BasePermission, SAFE_METHODS

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
