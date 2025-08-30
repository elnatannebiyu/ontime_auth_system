# Part 1: Backend User Model & Session Tracking

## Overview
This part establishes the foundation models for the complete auth system with session enforcement.

## 1.1 Update User Model

### Create migrations for User enhancements
```python
# accounts/models.py
from django.db import models
from django.contrib.auth.models import AbstractUser
from django.utils import timezone
import uuid

class User(AbstractUser):
    """Enhanced user model with session enforcement"""
    
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
        from sessions.models import Session
        self.sessions.update(revoked_at=timezone.now(), revoke_reason='user_banned')
        
    def soft_delete(self):
        """Soft delete user"""
        self.status = 'deleted'
        self.deleted_at = timezone.now()
        self.token_version += 1
        self.save()
        from sessions.models import Session
        self.sessions.update(revoked_at=timezone.now(), revoke_reason='user_deleted')
        
    def revoke_all_sessions(self):
        """Force re-login on all devices"""
        self.token_version += 1
        self.save()
        from sessions.models import Session
        self.sessions.update(revoked_at=timezone.now(), revoke_reason='forced_logout')
```

## 1.2 Create Session App

### Create the sessions app
```bash
cd authstack
python manage.py startapp sessions
```

### Add to INSTALLED_APPS
```python
# authstack/settings.py
INSTALLED_APPS = [
    # ... existing apps
    'accounts',
    'sessions',  # Add this
]
```

## 1.3 Session Models

### Create Session model
```python
# sessions/models.py
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
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='sessions')
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
        token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
        family = secrets.token_urlsafe(16)
        
        session = cls.objects.create(
            user=user,
            device=device,
            refresh_token_hash=token_hash,
            refresh_token_family=family,
            ip_address=cls._get_client_ip(request),
            user_agent=request.META.get('HTTP_USER_AGENT', ''),
            expires_at=timezone.now() + timedelta(days=30)
        )
        
        return session, refresh_token
    
    @staticmethod
    def _get_client_ip(request):
        """Get client IP from request"""
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            ip = x_forwarded_for.split(',')[0]
        else:
            ip = request.META.get('REMOTE_ADDR')
        return ip
    
    def rotate_token(self):
        """Rotate refresh token (prevent reuse)"""
        new_token = secrets.token_urlsafe(32)
        self.refresh_token_hash = hashlib.sha256(new_token.encode()).hexdigest()
        self.rotation_counter += 1
        self.last_used_at = timezone.now()
        self.save()
        return new_token
    
    def verify_token(self, token):
        """Verify refresh token matches"""
        token_hash = hashlib.sha256(token.encode()).hexdigest()
        return token_hash == self.refresh_token_hash
    
    def is_valid(self):
        """Check if session is still valid"""
        if self.revoked_at:
            return False
        if self.expires_at < timezone.now():
            return False
        if self.user.status != 'active':
            return False
        return True


class Device(models.Model):
    """Track user devices"""
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='devices')
    
    # Device identification
    install_id = models.UUIDField(db_index=True)
    platform = models.CharField(max_length=20)  # ios, android, web
    app_version = models.CharField(max_length=20)
    
    # Push notifications
    push_token = models.TextField(blank=True)
    push_platform = models.CharField(max_length=20, blank=True)  # fcm, apns
    
    # Metadata
    device_name = models.CharField(max_length=100, blank=True)
    device_model = models.CharField(max_length=100, blank=True)
    os_version = models.CharField(max_length=20, blank=True)
    last_seen_at = models.DateTimeField(auto_now=True)
    created_at = models.DateTimeField(auto_now_add=True)
    
    class Meta:
        db_table = 'user_devices'
        unique_together = ('user', 'install_id')
        indexes = [
            models.Index(fields=['user', '-last_seen_at']),
        ]
```

## 1.4 Admin Configuration

### Register models in admin
```python
# sessions/admin.py
from django.contrib import admin
from .models import Session, Device

@admin.register(Session)
class SessionAdmin(admin.ModelAdmin):
    list_display = ['id', 'user', 'device', 'created_at', 'last_used_at', 'revoked_at']
    list_filter = ['revoked_at', 'created_at']
    search_fields = ['user__username', 'user__email', 'ip_address']
    readonly_fields = ['id', 'refresh_token_hash', 'created_at', 'last_used_at']
    
    actions = ['revoke_sessions']
    
    def revoke_sessions(self, request, queryset):
        count = queryset.filter(revoked_at__isnull=True).update(
            revoked_at=timezone.now(),
            revoke_reason='admin_revoked'
        )
        self.message_user(request, f'{count} sessions revoked')
    
    revoke_sessions.short_description = 'Revoke selected sessions'

@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    list_display = ['id', 'user', 'platform', 'app_version', 'last_seen_at']
    list_filter = ['platform', 'created_at']
    search_fields = ['user__username', 'user__email', 'install_id']
    readonly_fields = ['id', 'created_at', 'last_seen_at']
```

## 1.5 Update Settings

### Add to settings.py
```python
# authstack/settings.py

# Custom user model
AUTH_USER_MODEL = 'accounts.User'

# Session settings
SESSION_EXPIRE_DAYS = 30
SESSION_REFRESH_ROTATION = True
SESSION_REUSE_DETECTION_WINDOW = 5  # seconds

# Cache for session management
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': 'redis://127.0.0.1:6379/1',
        'OPTIONS': {
            'CLIENT_CLASS': 'django_redis.client.DefaultClient',
        }
    }
}
```

## 1.6 Migrations

### Create and run migrations
```bash
python manage.py makemigrations accounts
python manage.py makemigrations sessions
python manage.py migrate
```

## Testing

### Test user status changes
```python
# Test in Django shell
python manage.py shell

from accounts.models import User
from sessions.models import Session, Device

# Create test user
user = User.objects.create_user(
    username='testuser',
    email='test@example.com',
    password='testpass123'
)

# Test ban functionality
user.ban('Test violation')
assert user.status == 'banned'
assert user.token_version == 2

# Test soft delete
user.soft_delete()
assert user.status == 'deleted'
assert user.deleted_at is not None
```

### API test endpoints
```python
# Test session creation
from django.test import RequestFactory
from sessions.models import Session

factory = RequestFactory()
request = factory.post('/login', HTTP_USER_AGENT='TestAgent')
request.META['REMOTE_ADDR'] = '127.0.0.1'

session, token = Session.create_session(user, request)
assert session.refresh_token_hash
assert token
assert session.is_valid()
```

## Next Steps

✅ User model enhanced with status tracking
✅ Session model for refresh token management  
✅ Device tracking for push notifications
✅ Admin interface for session management

Continue to [Part 2: JWT with Token Versioning](./part2-jwt-tokens.md)
