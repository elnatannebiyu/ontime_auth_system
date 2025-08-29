from django.db import models
from django.conf import settings
from django.contrib.auth.models import Group


class Membership(models.Model):
    """Link a user to a tenant with per-tenant roles (via Django Groups).

    A user may belong to many tenants; roles are scoped per-tenant.
    """

    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="memberships")
    tenant = models.ForeignKey("tenants.Tenant", on_delete=models.CASCADE, related_name="memberships")
    roles = models.ManyToManyField(Group, blank=True, related_name="tenant_memberships")

    class Meta:
        unique_together = ("user", "tenant")

    def __str__(self) -> str:
        return f"{self.user_id}@{self.tenant_id}"
