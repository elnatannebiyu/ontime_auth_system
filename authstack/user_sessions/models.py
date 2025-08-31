import hashlib
import secrets
import uuid
from datetime import timedelta
from django.db import models
from django.contrib.auth import get_user_model
from django.utils import timezone

User = get_user_model()


class Session(models.Model):
    """Tracks refresh tokens and sessions"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='refresh_sessions')
    device = models.ForeignKey('Device', on_delete=models.SET_NULL, null=True, blank=True)
    
    # Token management
    refresh_token_hash = models.CharField(max_length=128)
    refresh_token_family = models.CharField(max_length=64)  # For rotation tracking
    rotation_counter = models.IntegerField(default=0)
    
    # Revocation
    revoked_at = models.DateTimeField(null=True, blank=True)
    revoke_reason = models.CharField(max_length=50, blank=True)
    
    # Metadata
    ip_address = models.GenericIPAddressField()
    user_agent = models.TextField()
    created_at = models.DateTimeField(auto_now_add=True)
    last_used_at = models.DateTimeField(auto_now=True)
    expires_at = models.DateTimeField()
    
    class Meta:
        db_table = 'user_sessions'
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['refresh_token_family']),
            models.Index(fields=['revoked_at']),
        ]
    
    @classmethod
    def create_session(cls, user, request, device=None):
        """Create new session with refresh token"""
        refresh_token = secrets.token_urlsafe(32)
        refresh_token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
        family = secrets.token_urlsafe(16)
        
        session = cls.objects.create(
            user=user,
            device=device,
            refresh_token_hash=refresh_token_hash,
            refresh_token_family=family,
            ip_address=request.META.get('REMOTE_ADDR'),
            user_agent=request.META.get('HTTP_USER_AGENT', ''),
            expires_at=timezone.now() + timedelta(days=30)
        )
        return session, refresh_token
    
    def rotate_token(self):
        """Rotate refresh token (for security)"""
        new_token = secrets.token_urlsafe(32)
        self.refresh_token_hash = hashlib.sha256(new_token.encode()).hexdigest()
        self.rotation_counter += 1
        self.last_used_at = timezone.now()
        self.save()
        return new_token
    
    def is_valid(self):
        """Check if session is still valid"""
        if self.revoked_at:
            return False
        if timezone.now() > self.expires_at:
            return False
        return True


class Device(models.Model):
    """Track user devices for enhanced security"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='devices')
    
    # Device identification
    device_id = models.CharField(max_length=255, unique=True)
    device_name = models.CharField(max_length=255)
    device_type = models.CharField(max_length=50)  # ios, android, web
    device_model = models.CharField(max_length=255, blank=True)
    
    # Push notifications
    push_token = models.TextField(blank=True)
    push_enabled = models.BooleanField(default=False)
    
    # Trust status
    is_trusted = models.BooleanField(default=False)
    trusted_at = models.DateTimeField(null=True, blank=True)
    
    # Metadata
    created_at = models.DateTimeField(auto_now_add=True)
    last_seen_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'user_devices'
        indexes = [
            models.Index(fields=['user', '-last_seen_at']),
            models.Index(fields=['device_id']),
        ]
