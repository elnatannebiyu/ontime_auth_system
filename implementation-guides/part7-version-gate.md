# Part 7: Version Gate API

## Overview
Implement version checking and update enforcement for mobile apps.

## 7.1 Version Models

```python
# onchannels/models.py (extend existing or create new app)
import uuid
from django.db import models
from django.utils import timezone
from enum import Enum

class UpdateType(str, Enum):
    OPTIONAL = "optional"
    REQUIRED = "required"
    FORCED = "forced"

class VersionStatus(str, Enum):
    ACTIVE = "active"
    DEPRECATED = "deprecated"
    UNSUPPORTED = "unsupported"
    BLOCKED = "blocked"

class AppVersion(models.Model):
    """Track app versions and update requirements"""
    
    PLATFORM_CHOICES = [
        ('ios', 'iOS'),
        ('android', 'Android'),
        ('web', 'Web'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    
    # Version info
    platform = models.CharField(max_length=10, choices=PLATFORM_CHOICES, db_index=True)
    version = models.CharField(max_length=20, db_index=True)  # e.g., "1.2.3"
    build_number = models.IntegerField(default=0)  # e.g., 123
    version_code = models.IntegerField(default=0)  # Android version code
    
    # Status
    status = models.CharField(
        max_length=20,
        choices=[(s.value, s.value) for s in VersionStatus],
        default=VersionStatus.ACTIVE
    )
    
    # Update requirements
    min_supported_version = models.CharField(max_length=20, blank=True)
    update_type = models.CharField(
        max_length=20,
        choices=[(t.value, t.value) for t in UpdateType],
        default=UpdateType.OPTIONAL
    )
    
    # Update info
    update_title = models.CharField(max_length=100, default="Update Available")
    update_message = models.TextField(
        default="A new version is available. Please update for the best experience."
    )
    force_update_message = models.TextField(
        default="This version is no longer supported. Please update to continue."
    )
    
    # Store URLs
    ios_store_url = models.URLField(blank=True)
    android_store_url = models.URLField(blank=True)
    
    # Features
    features = models.JSONField(default=list, blank=True)  # ["feature1", "feature2"]
    changelog = models.TextField(blank=True)
    
    # Dates
    released_at = models.DateTimeField(default=timezone.now)
    deprecated_at = models.DateTimeField(null=True, blank=True)
    end_of_support_at = models.DateTimeField(null=True, blank=True)
    
    # Metadata
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'app_versions'
        unique_together = [['platform', 'version']]
        indexes = [
            models.Index(fields=['platform', '-released_at']),
            models.Index(fields=['platform', 'status']),
        ]
        ordering = ['platform', '-released_at']
    
    def __str__(self):
        return f"{self.platform} v{self.version}"
    
    @classmethod
    def get_latest_version(cls, platform):
        """Get latest active version for platform"""
        return cls.objects.filter(
            platform=platform,
            status=VersionStatus.ACTIVE
        ).order_by('-released_at').first()
    
    def compare_version(self, other_version):
        """Compare version strings (semantic versioning)"""
        def version_tuple(v):
            return tuple(map(int, v.split('.')))
        
        try:
            return version_tuple(self.version) > version_tuple(other_version)
        except:
            return False

class FeatureFlag(models.Model):
    """Control feature availability by version"""
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    
    # Feature info
    name = models.CharField(max_length=50, unique=True, db_index=True)
    description = models.TextField(blank=True)
    
    # Availability
    enabled = models.BooleanField(default=False)
    enabled_for_staff = models.BooleanField(default=True)
    
    # Version control
    min_ios_version = models.CharField(max_length=20, blank=True)
    min_android_version = models.CharField(max_length=20, blank=True)
    
    # Rollout percentage (0-100)
    rollout_percentage = models.IntegerField(default=100)
    
    # User targeting
    enabled_users = models.JSONField(default=list)  # List of user IDs
    disabled_users = models.JSONField(default=list)  # List of user IDs
    
    # Dates
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    
    class Meta:
        db_table = 'feature_flags'
    
    def is_enabled_for_version(self, platform, version):
        """Check if feature is enabled for specific version"""
        if not self.enabled:
            return False
        
        if platform == 'ios' and self.min_ios_version:
            return self._compare_versions(version, self.min_ios_version)
        elif platform == 'android' and self.min_android_version:
            return self._compare_versions(version, self.min_android_version)
        
        return True
    
    def _compare_versions(self, version, min_version):
        """Compare semantic versions"""
        def version_tuple(v):
            return tuple(map(int, v.split('.')))
        
        try:
            return version_tuple(version) >= version_tuple(min_version)
        except:
            return False
```

## 7.2 Version Check Service

```python
# onchannels/version_service.py
from typing import Dict, Tuple, Optional
from onchannels.models import AppVersion, FeatureFlag, UpdateType, VersionStatus
import random

class VersionCheckService:
    """Service for version checking and feature flags"""
    
    @staticmethod
    def check_version(platform: str, current_version: str, 
                     build_number: int = None) -> Dict:
        """Check if app version needs update"""
        
        # Get latest version
        latest = AppVersion.get_latest_version(platform)
        if not latest:
            return {
                'update_required': False,
                'message': 'Version check unavailable'
            }
        
        # Get current version info
        try:
            current = AppVersion.objects.get(
                platform=platform,
                version=current_version
            )
        except AppVersion.DoesNotExist:
            # Unknown version - might be very old
            return {
                'update_required': True,
                'update_type': UpdateType.FORCED,
                'message': 'Your app version is not recognized. Please update.',
                'latest_version': latest.version,
                'store_url': _get_store_url(platform, latest)
            }
        
        # Check version status
        if current.status == VersionStatus.BLOCKED:
            return {
                'update_required': True,
                'update_type': UpdateType.FORCED,
                'message': current.force_update_message,
                'latest_version': latest.version,
                'store_url': _get_store_url(platform, latest),
                'blocked': True
            }
        
        if current.status == VersionStatus.UNSUPPORTED:
            return {
                'update_required': True,
                'update_type': UpdateType.FORCED,
                'message': current.force_update_message or 'This version is no longer supported.',
                'latest_version': latest.version,
                'store_url': _get_store_url(platform, latest)
            }
        
        # Check if update available
        if current.version != latest.version:
            # Determine update type based on minimum supported version
            if latest.min_supported_version:
                if not _version_meets_minimum(current_version, latest.min_supported_version):
                    update_type = UpdateType.FORCED
                    message = latest.force_update_message
                else:
                    update_type = latest.update_type or UpdateType.OPTIONAL
                    message = latest.update_message
            else:
                update_type = latest.update_type or UpdateType.OPTIONAL
                message = latest.update_message
            
            return {
                'update_required': update_type != UpdateType.OPTIONAL,
                'update_available': True,
                'update_type': update_type,
                'message': message,
                'latest_version': latest.version,
                'current_version': current_version,
                'store_url': _get_store_url(platform, latest),
                'changelog': latest.changelog,
                'features': latest.features
            }
        
        # No update needed
        return {
            'update_required': False,
            'update_available': False,
            'message': 'Your app is up to date',
            'current_version': current_version,
            'latest_version': latest.version
        }
    
    @staticmethod
    def get_feature_flags(user_id: str, platform: str, 
                         version: str, is_staff: bool = False) -> Dict[str, bool]:
        """Get enabled feature flags for user"""
        flags = {}
        
        for feature in FeatureFlag.objects.filter(enabled=True):
            # Check staff override
            if is_staff and feature.enabled_for_staff:
                flags[feature.name] = True
                continue
            
            # Check user-specific rules
            if user_id in feature.disabled_users:
                flags[feature.name] = False
                continue
            
            if user_id in feature.enabled_users:
                flags[feature.name] = True
                continue
            
            # Check version compatibility
            if not feature.is_enabled_for_version(platform, version):
                flags[feature.name] = False
                continue
            
            # Check rollout percentage
            if feature.rollout_percentage < 100:
                # Use consistent hashing for user
                user_hash = hash(f"{user_id}{feature.name}") % 100
                flags[feature.name] = user_hash < feature.rollout_percentage
            else:
                flags[feature.name] = True
        
        return flags

def _get_store_url(platform: str, version: AppVersion) -> str:
    """Get app store URL for platform"""
    if platform == 'ios':
        return version.ios_store_url or 'https://apps.apple.com/app/id123456789'
    elif platform == 'android':
        return version.android_store_url or 'https://play.google.com/store/apps/details?id=com.example.app'
    return ''

def _version_meets_minimum(version: str, min_version: str) -> bool:
    """Check if version meets minimum requirement"""
    def version_tuple(v):
        return tuple(map(int, v.split('.')))
    
    try:
        return version_tuple(version) >= version_tuple(min_version)
    except:
        return False
```

## 7.3 Version API Views

```python
# onchannels/views.py
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from onchannels.version_service import VersionCheckService
from onchannels.models import AppVersion, FeatureFlag
from django.utils import timezone

@api_view(['POST'])
@permission_classes([AllowAny])
def check_version_view(request):
    """Check app version and get update info"""
    platform = request.data.get('platform', '').lower()
    version = request.data.get('version', '')
    build_number = request.data.get('build_number')
    
    # Validate input
    if not platform or not version:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Platform and version required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    if platform not in ['ios', 'android', 'web']:
        return Response({
            'code': 'INVALID_PLATFORM',
            'message': f'Invalid platform: {platform}'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Check version
    result = VersionCheckService.check_version(platform, version, build_number)
    
    # Add timestamp
    result['checked_at'] = timezone.now().isoformat()
    
    # Add feature flags if user is authenticated
    if request.user.is_authenticated:
        result['features'] = VersionCheckService.get_feature_flags(
            user_id=str(request.user.id),
            platform=platform,
            version=version,
            is_staff=request.user.is_staff
        )
    
    return Response(result, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_feature_flags_view(request):
    """Get feature flags for authenticated user"""
    platform = request.GET.get('platform', 'web').lower()
    version = request.GET.get('version', '1.0.0')
    
    flags = VersionCheckService.get_feature_flags(
        user_id=str(request.user.id),
        platform=platform,
        version=version,
        is_staff=request.user.is_staff
    )
    
    return Response({
        'features': flags,
        'user_id': str(request.user.id),
        'platform': platform,
        'version': version
    }, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_latest_version_view(request):
    """Get latest version info for platform"""
    platform = request.GET.get('platform', '').lower()
    
    if not platform:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Platform required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    latest = AppVersion.get_latest_version(platform)
    
    if not latest:
        return Response({
            'code': 'NOT_FOUND',
            'message': f'No version found for {platform}'
        }, status=status.HTTP_404_NOT_FOUND)
    
    return Response({
        'platform': platform,
        'version': latest.version,
        'build_number': latest.build_number,
        'released_at': latest.released_at.isoformat(),
        'features': latest.features,
        'changelog': latest.changelog,
        'store_url': _get_store_url_for_response(platform, latest)
    }, status=status.HTTP_200_OK)

@api_view(['GET'])
@permission_classes([AllowAny])
def get_supported_versions_view(request):
    """Get all supported versions for platform"""
    platform = request.GET.get('platform', '').lower()
    
    if not platform:
        # Return all platforms
        versions = AppVersion.objects.filter(
            status__in=['active', 'deprecated']
        ).order_by('platform', '-released_at')
    else:
        versions = AppVersion.objects.filter(
            platform=platform,
            status__in=['active', 'deprecated']
        ).order_by('-released_at')
    
    data = []
    for version in versions:
        data.append({
            'platform': version.platform,
            'version': version.version,
            'status': version.status,
            'released_at': version.released_at.isoformat(),
            'deprecated': version.status == 'deprecated',
            'end_of_support': version.end_of_support_at.isoformat() if version.end_of_support_at else None
        })
    
    return Response({
        'versions': data,
        'count': len(data)
    }, status=status.HTTP_200_OK)

def _get_store_url_for_response(platform, version):
    """Helper to get store URL"""
    if platform == 'ios':
        return version.ios_store_url
    elif platform == 'android':
        return version.android_store_url
    return None
```

## 7.4 Admin Configuration

```python
# onchannels/admin.py
from django.contrib import admin
from onchannels.models import AppVersion, FeatureFlag

@admin.register(AppVersion)
class AppVersionAdmin(admin.ModelAdmin):
    list_display = ['platform', 'version', 'status', 'update_type', 'released_at']
    list_filter = ['platform', 'status', 'update_type']
    search_fields = ['version', 'update_title']
    ordering = ['platform', '-released_at']
    
    fieldsets = (
        ('Version Info', {
            'fields': ('platform', 'version', 'build_number', 'version_code')
        }),
        ('Status', {
            'fields': ('status', 'update_type', 'min_supported_version')
        }),
        ('Update Messages', {
            'fields': ('update_title', 'update_message', 'force_update_message')
        }),
        ('Store Links', {
            'fields': ('ios_store_url', 'android_store_url')
        }),
        ('Release Info', {
            'fields': ('features', 'changelog', 'released_at', 'deprecated_at', 'end_of_support_at')
        }),
    )

@admin.register(FeatureFlag)
class FeatureFlagAdmin(admin.ModelAdmin):
    list_display = ['name', 'enabled', 'rollout_percentage', 'enabled_for_staff']
    list_filter = ['enabled', 'enabled_for_staff']
    search_fields = ['name', 'description']
    
    fieldsets = (
        ('Feature Info', {
            'fields': ('name', 'description')
        }),
        ('Availability', {
            'fields': ('enabled', 'enabled_for_staff', 'rollout_percentage')
        }),
        ('Version Requirements', {
            'fields': ('min_ios_version', 'min_android_version')
        }),
        ('User Targeting', {
            'fields': ('enabled_users', 'disabled_users')
        }),
    )
```

## 7.5 Update URLs

```python
# onchannels/urls.py
from django.urls import path
from . import views

urlpatterns = [
    path('version/check/', views.check_version_view, name='check_version'),
    path('version/latest/', views.get_latest_version_view, name='latest_version'),
    path('version/supported/', views.get_supported_versions_view, name='supported_versions'),
    path('features/', views.get_feature_flags_view, name='feature_flags'),
]
```

```python
# authstack/urls.py (add to existing)
urlpatterns = [
    # ... existing URLs
    path('api/', include('onchannels.urls')),
]
```

## 7.6 Migration to Create Tables

```bash
python manage.py makemigrations onchannels
python manage.py migrate
```

## Testing

### Check version
```bash
curl -X POST http://localhost:8000/api/version/check/ \
  -H "Content-Type: application/json" \
  -d '{
    "platform": "ios",
    "version": "1.0.0",
    "build_number": 100
  }'
```

### Get latest version
```bash
curl -X GET "http://localhost:8000/api/version/latest/?platform=android"
```

### Get feature flags
```bash
curl -X GET "http://localhost:8000/api/features/?platform=ios&version=1.2.0" \
  -H "Authorization: Bearer ACCESS_TOKEN"
```

## Sample Version Data

```python
# Create sample versions in Django shell
from onchannels.models import AppVersion, FeatureFlag

# iOS versions
AppVersion.objects.create(
    platform='ios',
    version='1.0.0',
    build_number=100,
    status='deprecated',
    update_type='optional'
)

AppVersion.objects.create(
    platform='ios',
    version='1.1.0',
    build_number=110,
    status='active',
    update_type='optional',
    min_supported_version='1.0.0'
)

AppVersion.objects.create(
    platform='ios',
    version='1.2.0',
    build_number=120,
    status='active',
    update_type='required',
    min_supported_version='1.1.0',
    features=['dark_mode', 'biometric_auth'],
    changelog='- Added dark mode\n- Biometric authentication\n- Bug fixes'
)

# Feature flags
FeatureFlag.objects.create(
    name='dark_mode',
    description='Enable dark mode UI',
    enabled=True,
    min_ios_version='1.2.0',
    min_android_version='1.2.0',
    rollout_percentage=100
)

FeatureFlag.objects.create(
    name='social_login',
    description='Enable social authentication',
    enabled=True,
    rollout_percentage=50  # A/B testing
)
```

## Flutter Integration Notes

1. **App Launch**: Check version on app start
2. **Update Dialog**: Show appropriate dialog based on update type
3. **Force Update**: Block app usage if forced update required
4. **Feature Flags**: Cache and check feature availability
5. **Store Redirect**: Open app store for updates

## Security Considerations

1. **Version Spoofing**: Validate version format
2. **Rate Limiting**: Limit version check frequency
3. **Cache Results**: Cache version check for period
4. **Secure Features**: Don't expose sensitive feature flags
5. **Admin Only**: Restrict version management to admins

## Next Steps

✅ Version tracking models
✅ Version check service
✅ Update enforcement logic
✅ Feature flag system
✅ Admin interface

Continue to [Part 8: Flutter Session Management](./part8-flutter-session.md)
