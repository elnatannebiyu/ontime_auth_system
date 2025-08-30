import uuid
from django.db import models
from django.conf import settings
from django.contrib.auth.models import Group
from django.utils import timezone


class UserSession(models.Model):
    """Track user sessions for security and device management"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='sessions')
    
    # Device information
    device_id = models.CharField(max_length=255, db_index=True)
    device_name = models.CharField(max_length=255, blank=True)
    device_type = models.CharField(max_length=50, blank=True)  # mobile, desktop, tablet
    
    # Session metadata
    ip_address = models.GenericIPAddressField()
    user_agent = models.TextField()
    location = models.CharField(max_length=255, blank=True)  # City, Country
    
    # Token tracking
    refresh_token_jti = models.CharField(max_length=255, unique=True, db_index=True)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    last_activity = models.DateTimeField(auto_now=True)
    expires_at = models.DateTimeField()
    
    # Status
    is_active = models.BooleanField(default=True)
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoke_reason = models.CharField(max_length=255, blank=True)
    
    class Meta:
        ordering = ['-last_activity']
        indexes = [
            models.Index(fields=['user', 'is_active']),
            models.Index(fields=['refresh_token_jti']),
        ]
    
    def __str__(self):
        return f"{self.user.username} - {self.device_name or self.device_id[:8]}"
    
    def revoke(self, reason=''):
        """Revoke this session"""
        self.is_active = False
        self.revoked_at = timezone.now()
        self.revoke_reason = reason
        self.save()


class LoginAttempt(models.Model):
    """Track login attempts for security monitoring"""
    username = models.CharField(max_length=255, db_index=True)
    ip_address = models.GenericIPAddressField(db_index=True)
    user_agent = models.TextField()
    
    success = models.BooleanField(default=False)
    failure_reason = models.CharField(max_length=255, blank=True)
    
    timestamp = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        ordering = ['-timestamp']
        indexes = [
            models.Index(fields=['username', 'timestamp']),
            models.Index(fields=['ip_address', 'timestamp']),
        ]


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
