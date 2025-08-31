# THIS FILE IS NOT CURRENTLY USED - DUPLICATE OF models_enhanced.py
# The project uses Django's default User model
# This file appears to be an earlier version of models_enhanced.py
# TO BE REMOVED after confirming no dependencies

from django.contrib.auth.models import AbstractUser
from django.db import models
from django.utils import timezone


class User(AbstractUser):
    """Extended User model with enhanced security and profile fields
    
    NOTE: This is a duplicate/earlier version of models_enhanced.py
    Neither file is currently active - using Django's default User model
    """
    
    # Session enforcement fields
    STATUS_CHOICES = [
        ('active', 'Active'),
        ('banned', 'Banned'), 
        ('deleted', 'Deleted'),
        ('disabled', 'Disabled'),
    ]
    
    status = models.CharField(max_length=20, choices=STATUS_CHOICES, default='active')
    token_version = models.IntegerField(default=1)
    banned_reason = models.TextField(blank=True, null=True)
    deleted_at = models.DateTimeField(null=True, blank=True)
    
    # Authentication fields
    phone_e164 = models.CharField(max_length=20, blank=True, null=True, unique=True, db_index=True)
    email_verified = models.BooleanField(default=False)
    phone_verified = models.BooleanField(default=False)
    
    # Profile fields
    birth_date = models.DateField(null=True, blank=True)
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
        from accounts.models import UserSession
        UserSession.objects.filter(user=self).update(
            is_active=False,
            revoked_at=timezone.now(),
            revoke_reason='user_banned'
        )
        
    def soft_delete(self):
        """Soft delete user"""
        self.status = 'deleted'
        self.deleted_at = timezone.now()
        self.token_version += 1
        self.save()
        from accounts.models import UserSession
        UserSession.objects.filter(user=self).update(
            is_active=False,
            revoked_at=timezone.now(),
            revoke_reason='user_deleted'
        )
        
    def revoke_all_sessions(self):
        """Force re-login on all devices"""
        self.token_version += 1
        self.save()
        from accounts.models import UserSession
        UserSession.objects.filter(user=self).update(
            is_active=False,
            revoked_at=timezone.now(),
            revoke_reason='forced_logout'
        )
