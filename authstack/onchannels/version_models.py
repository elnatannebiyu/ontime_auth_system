"""Version tracking and feature flag models for app updates"""
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
        default=VersionStatus.ACTIVE.value
    )
    
    # Update requirements
    min_supported_version = models.CharField(max_length=20, blank=True)
    update_type = models.CharField(
        max_length=20,
        choices=[(t.value, t.value) for t in UpdateType],
        default=UpdateType.OPTIONAL.value
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
        db_table = 'channels_appversion'
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
        db_table = 'channels_featureflag'
    
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
