import uuid
from django.db import models
from django.conf import settings
from django.contrib.auth.models import Group
from django.utils import timezone
from django.contrib.auth import get_user_model


class UserSession(models.Model):
    """Track user sessions for security and device management"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='sessions')
    
    # Device information
    device_id = models.CharField(max_length=255, db_index=True)
    device_name = models.CharField(max_length=255, blank=True)
    device_type = models.CharField(max_length=50, blank=True)  # mobile, desktop, tablet
    os_name = models.CharField(max_length=50, blank=True)
    os_version = models.CharField(max_length=50, blank=True)
    
    # Session metadata
    ip_address = models.GenericIPAddressField()
    user_agent = models.TextField()
    location = models.CharField(max_length=255, blank=True)  # City, Country
    
    # Token tracking
    refresh_token_jti = models.CharField(max_length=255, unique=True, db_index=True)
    access_token_jti = models.CharField(max_length=255, blank=True, db_index=True)  # Track current access token
    
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


class SocialAccount(models.Model):
    """Store social auth provider data"""
    
    PROVIDER_CHOICES = [
        ('google', 'Google'),
        ('apple', 'Apple'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name='social_accounts')
    
    provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES)
    provider_id = models.CharField(max_length=255, db_index=True)
    
    # OAuth data
    access_token = models.TextField(blank=True)
    refresh_token = models.TextField(blank=True)
    token_expires_at = models.DateTimeField(null=True, blank=True)
    
    # Profile data
    email = models.EmailField(blank=True)
    name = models.CharField(max_length=255, blank=True)
    picture_url = models.URLField(blank=True)
    extra_data = models.JSONField(default=dict)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    last_login = models.DateTimeField(null=True, blank=True)
    
    class Meta:
        db_table = 'social_accounts'
        unique_together = [['provider', 'provider_id']]
        indexes = [
            models.Index(fields=['provider', 'provider_id']),
        ]
    
    def __str__(self):
        return f"{self.user.username} - {self.provider}"


class UserProfile(models.Model):
    """Per-user profile extension for additional security/account fields.

    We keep this separate so we can continue using Django's default User model
    while storing flags like email verification.
    """

    user = models.OneToOneField(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="profile",
    )
    email_verified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["email_verified"]),
        ]

    def __str__(self) -> str:  # pragma: no cover - trivial
        return f"Profile<{self.user_id}>"


class ActionToken(models.Model):
    """One-time tokens for account actions (email verify, logout-all, delete).

    Purpose values (convention):
    - verify_email
    - confirm_logout_all
    - confirm_account_delete
    - reset_password
    """

    PURPOSE_VERIFY_EMAIL = "verify_email"
    PURPOSE_CONFIRM_ACCOUNT_DELETE = "confirm_account_delete"
    PURPOSE_RESET_PASSWORD = "reset_password"
    # Added for OTP gating of sensitive actions
    PURPOSE_CONFIRM_PASSWORD_CHANGE = "confirm_password_change"
    PURPOSE_CONFIRM_PASSWORD_ENABLE = "confirm_password_enable"

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    user = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        on_delete=models.CASCADE,
        related_name="action_tokens",
    )
    purpose = models.CharField(max_length=64, db_index=True)
    token = models.CharField(max_length=255, unique=True, db_index=True)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    used = models.BooleanField(default=False)

    class Meta:
        indexes = [
            models.Index(fields=["user", "purpose", "used"]),
            models.Index(fields=["expires_at"]),
        ]

    def __str__(self) -> str:  # pragma: no cover - trivial
        return f"ActionToken<{self.purpose}:{self.user_id}>"
