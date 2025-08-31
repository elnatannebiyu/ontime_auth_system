# THIS FILE IS NOT CURRENTLY USED
# The project uses Django's default User model
# These models were created for enhanced user features but are not active
# To activate: Set AUTH_USER_MODEL = 'accounts.User' in settings.py
# and create/run migrations

import uuid
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone
from django.conf import settings


class User(AbstractUser):
    """Enhanced user model with session enforcement
    
    This custom User model extends Django's AbstractUser with:
    - Session enforcement and token versioning
    - User status management (active, banned, deleted, disabled)
    - Phone number authentication support
    - Social authentication fields
    - Enhanced security tracking
    - Soft delete functionality
    
    NOTE: Not currently active - using Django's default User model
    """
    
    # Session enforcement fields
    STATUS_CHOICES = [
        ('active', 'Active'),
        ('banned', 'Banned'), 
        ('deleted', 'Deleted'),
        ('disabled', 'Disabled'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    token_version = models.IntegerField(default=1)
    banned_reason = models.TextField(blank=True, null=True)
    deleted_at = models.DateTimeField(null=True, blank=True)
    
    # Authentication fields
    phone_e164 = models.CharField(max_length=20, blank=True, null=True, unique=True, db_index=True)
    email_verified = models.BooleanField(default=False)
    phone_verified = models.BooleanField(default=False)
    
    # Profile fields from account creation standard
    birth_date = models.DateField(null=True, blank=True)
    created_date = models.DateTimeField(auto_now_add=True)
    tos_accepted_at = models.DateTimeField(null=True, blank=True)
    privacy_accepted_at = models.DateTimeField(null=True, blank=True)
    marketing_consent = models.BooleanField(default=False)
    
    # Social auth fields
    google_id = models.CharField(max_length=255, blank=True, null=True, unique=True)
    apple_id = models.CharField(max_length=255, blank=True, null=True, unique=True)
    
    # Security fields (from our previous implementation)
    failed_login_attempts = models.IntegerField(default=0)
    last_failed_login = models.DateTimeField(null=True, blank=True)
    lockout_until = models.DateTimeField(null=True, blank=True)
    password_changed_at = models.DateTimeField(auto_now_add=True)
    must_change_password = models.BooleanField(default=False)
    
    class Meta:
        db_table = 'auth_user'
        indexes = [
            models.Index(fields=['email']),
            models.Index(fields=['phone_e164']),
            models.Index(fields=['status']),
        ]
    
    def ban(self, reason=''):
        """Ban user and invalidate all sessions"""
        self.status = 'banned'
        self.banned_reason = reason
        self.token_version += 1
        self.save()
        # Revoke all sessions
        self.sessions.update(revoked_at=timezone.now(), revoke_reason='user_banned')
        
    def soft_delete(self):
        """Soft delete user"""
        self.status = 'deleted'
        self.deleted_at = timezone.now()
        self.token_version += 1
        self.save()
        self.sessions.update(revoked_at=timezone.now(), revoke_reason='user_deleted')
        
    def revoke_all_sessions(self):
        """Force re-login on all devices"""
        self.token_version += 1
        self.save()
        self.sessions.update(revoked_at=timezone.now(), revoke_reason='forced_logout')


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
    from django.contrib.auth.models import Group
    
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.CASCADE, related_name="memberships")
    tenant = models.ForeignKey("tenants.Tenant", on_delete=models.CASCADE, related_name="memberships")
    roles = models.ManyToManyField(Group, blank=True, related_name="tenant_memberships")

    class Meta:
        unique_together = ("user", "tenant")

    def __str__(self) -> str:
        return f"{self.user_id}@{self.tenant_id}"
