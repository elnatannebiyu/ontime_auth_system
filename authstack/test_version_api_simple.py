#!/usr/bin/env python
"""Simple test script for Version Gate API functionality"""
import os
import sys
import django

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'authstack.settings')
django.setup()

from onchannels.version_models import AppVersion, FeatureFlag, VersionStatus, UpdateType
from onchannels.version_service import VersionCheckService
from django.contrib.auth import get_user_model

User = get_user_model()

def test_version_models():
    """Test that version models can be imported and used"""
    print("Testing Version Models...")
    
    # Test creating an AppVersion instance (in memory only)
    app_version = AppVersion(
        platform='ios',
        version='1.2.0',
        build_number=120,
        status=VersionStatus.ACTIVE,
        update_type=UpdateType.OPTIONAL,
        features=['dark_mode', 'biometric_auth'],
        changelog='- Added dark mode\n- Biometric authentication'
    )
    print(f"✓ Created AppVersion: {app_version.platform} {app_version.version}")
    
    # Test creating a FeatureFlag instance (in memory only)
    feature_flag = FeatureFlag(
        name='dark_mode',
        description='Enable dark mode UI',
        enabled=True,
        rollout_percentage=100,
        min_ios_version='1.2.0'
    )
    print(f"✓ Created FeatureFlag: {feature_flag.name}")
    
    return True

def test_version_service():
    """Test that version service logic works"""
    print("\nTesting Version Service...")
    
    service = VersionCheckService()
    
    # Test version comparison
    result = service._compare_versions('1.2.0', '1.1.0')
    assert result > 0, "1.2.0 should be greater than 1.1.0"
    print("✓ Version comparison works: 1.2.0 > 1.1.0")
    
    result = service._compare_versions('1.0.0', '1.0.0')
    assert result == 0, "1.0.0 should equal 1.0.0"
    print("✓ Version comparison works: 1.0.0 == 1.0.0")
    
    result = service._compare_versions('1.0.0', '2.0.0')
    assert result < 0, "1.0.0 should be less than 2.0.0"
    print("✓ Version comparison works: 1.0.0 < 2.0.0")
    
    # Test version parsing
    parsed = service._parse_version('1.2.3')
    assert parsed == (1, 2, 3), f"Expected (1, 2, 3), got {parsed}"
    print("✓ Version parsing works: '1.2.3' -> (1, 2, 3)")
    
    return True

def test_version_views():
    """Test that version views can be imported"""
    print("\nTesting Version Views...")
    
    from onchannels import version_views
    
    # Check that views exist
    assert hasattr(version_views, 'check_version_view'), "check_version_view not found"
    print("✓ check_version_view exists")
    
    assert hasattr(version_views, 'get_feature_flags_view'), "get_feature_flags_view not found"
    print("✓ get_feature_flags_view exists")
    
    assert hasattr(version_views, 'get_latest_version_view'), "get_latest_version_view not found"
    print("✓ get_latest_version_view exists")
    
    assert hasattr(version_views, 'get_supported_versions_view'), "get_supported_versions_view not found"
    print("✓ get_supported_versions_view exists")
    
    return True

def test_admin_registration():
    """Test that admin classes are registered"""
    print("\nTesting Admin Registration...")
    
    from django.contrib import admin
    from onchannels.version_models import AppVersion, FeatureFlag
    
    # Check if models are registered in admin
    try:
        admin.site._registry[AppVersion]
        print("✓ AppVersion registered in admin")
    except KeyError:
        print("✗ AppVersion not registered in admin")
        return False
    
    try:
        admin.site._registry[FeatureFlag]
        print("✓ FeatureFlag registered in admin")
    except KeyError:
        print("✗ FeatureFlag not registered in admin")
        return False
    
    return True

def test_url_patterns():
    """Test that URL patterns are configured"""
    print("\nTesting URL Patterns...")
    
    from django.urls import resolve, reverse
    from django.urls.exceptions import NoReverseMatch
    
    # Test version check URL
    try:
        url = reverse('check_version')
        print(f"✓ check_version URL: {url}")
    except NoReverseMatch:
        print("✗ check_version URL not found")
        return False
    
    # Test feature flags URL
    try:
        url = reverse('feature_flags')
        print(f"✓ feature_flags URL: {url}")
    except NoReverseMatch:
        print("✗ feature_flags URL not found")
        return False
    
    # Test latest version URL
    try:
        url = reverse('latest_version')
        print(f"✓ latest_version URL: {url}")
    except NoReverseMatch:
        print("✗ latest_version URL not found")
        return False
    
    # Test supported versions URL
    try:
        url = reverse('supported_versions')
        print(f"✓ supported_versions URL: {url}")
    except NoReverseMatch:
        print("✗ supported_versions URL not found")
        return False
    
    return True

def main():
    """Run all tests"""
    print("=" * 50)
    print("Version Gate API Functionality Tests")
    print("=" * 50)
    
    all_passed = True
    
    try:
        if not test_version_models():
            all_passed = False
    except Exception as e:
        print(f"✗ Version models test failed: {e}")
        all_passed = False
    
    try:
        if not test_version_service():
            all_passed = False
    except Exception as e:
        print(f"✗ Version service test failed: {e}")
        all_passed = False
    
    try:
        if not test_version_views():
            all_passed = False
    except Exception as e:
        print(f"✗ Version views test failed: {e}")
        all_passed = False
    
    try:
        if not test_admin_registration():
            all_passed = False
    except Exception as e:
        print(f"✗ Admin registration test failed: {e}")
        all_passed = False
    
    try:
        if not test_url_patterns():
            all_passed = False
    except Exception as e:
        print(f"✗ URL patterns test failed: {e}")
        all_passed = False
    
    print("\n" + "=" * 50)
    if all_passed:
        print("✅ All tests passed!")
        print("\nNote: Database migrations are still needed to fully use the API.")
        print("The migration issue appears to be related to app naming conflicts.")
    else:
        print("❌ Some tests failed")
        sys.exit(1)
    
    print("=" * 50)

if __name__ == '__main__':
    main()
