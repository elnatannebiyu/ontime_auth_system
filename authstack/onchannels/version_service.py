"""Service for version checking and feature flags"""
from typing import Dict, Optional
from onchannels.version_models import AppVersion, FeatureFlag, UpdateType, VersionStatus


class VersionCheckService:
    """Service for checking app versions and feature flags"""
    
    @staticmethod
    def _parse_version(version: str) -> tuple:
        """Parse version string into tuple for comparison"""
        try:
            parts = version.split('.')
            return tuple(int(p) for p in parts)
        except (ValueError, AttributeError):
            return (0, 0, 0)
    
    @staticmethod
    def _compare_versions(version1: str, version2: str) -> int:
        """Compare two version strings
        Returns: -1 if version1 < version2, 0 if equal, 1 if version1 > version2
        """
        v1_tuple = VersionCheckService._parse_version(version1)
        v2_tuple = VersionCheckService._parse_version(version2)
        
        if v1_tuple < v2_tuple:
            return -1
        elif v1_tuple > v2_tuple:
            return 1
        else:
            return 0
    
    @staticmethod
    def check_version(platform: str, version: str, build_number: int = None) -> dict:
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
                version=version
            )
        except AppVersion.DoesNotExist:
            # Unknown version - might be very old
            return {
                'update_required': True,
                'update_available': True,
                'update_type': UpdateType.FORCED.value,
                'message': 'Your app version is not recognized. Please update.',
                'current_version': version,
                'latest_version': latest.version,
                'store_url': _get_store_url(platform, latest)
            }
        
        # Check version status
        if current.status == VersionStatus.BLOCKED.value:
            return {
                'update_required': True,
                'update_type': UpdateType.FORCED.value,
                'message': current.force_update_message,
                'latest_version': latest.version,
                'store_url': _get_store_url(platform, latest),
                'blocked': True
            }
        
        if current.status == VersionStatus.UNSUPPORTED.value:
            return {
                'update_required': True,
                'update_type': UpdateType.FORCED.value,
                'message': current.force_update_message or 'This version is no longer supported.',
                'latest_version': latest.version,
                'store_url': _get_store_url(platform, latest)
            }
        
        # Check if update available
        if current.version != latest.version:
            # Determine update type based on minimum supported version
            if latest.min_supported_version:
                if not _version_meets_minimum(version, latest.min_supported_version):
                    update_type = UpdateType.FORCED.value
                    message = latest.force_update_message
                else:
                    update_type = latest.update_type or UpdateType.OPTIONAL.value
                    message = latest.update_message
            else:
                update_type = latest.update_type or UpdateType.OPTIONAL.value
                message = latest.update_message
            
            return {
                'update_required': update_type != UpdateType.OPTIONAL.value,
                'update_available': True,
                'update_type': update_type,
                'message': message,
                'latest_version': latest.version,
                'current_version': version,
                'store_url': _get_store_url(platform, latest),
                'changelog': latest.changelog,
                'features': latest.features
            }
        
        # No update needed
        return {
            'update_required': False,
            'update_available': False,
            'message': 'Your app is up to date',
            'current_version': version,
            'latest_version': latest.version
        }
    
    @staticmethod
    def get_feature_flags(user_id: str, platform: str, 
                         version: str, is_staff: bool = False) -> Dict[str, bool]:
        """Get enabled feature flags for user"""
        flags = {}
        
        # Get all features, not just enabled ones (to check staff overrides)
        for feature in FeatureFlag.objects.all():
            # Check staff override first
            if is_staff and feature.enabled_for_staff:
                flags[feature.name] = True
                continue
            
            # Skip if not enabled globally
            if not feature.enabled:
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
