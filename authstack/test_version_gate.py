"""Tests for Version Gate API"""
import json
from django.test import TestCase
from django.contrib.auth import get_user_model
from rest_framework.test import APIClient
from rest_framework import status
from onchannels.version_models import AppVersion, FeatureFlag, UpdateType, VersionStatus
from datetime import datetime, timedelta
from django.utils import timezone
from tenants.models import Tenant

User = get_user_model()


class VersionGateAPITestCase(TestCase):
    """Test cases for version checking and feature flags"""
    
    def setUp(self):
        """Set up test data"""
        self.client = APIClient()
        
        # Create test tenant
        self.tenant = Tenant.objects.create(
            slug='default',
            name='Default Tenant',
            active=True
        )
        
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        
        # Create test versions
        self.ios_v1 = AppVersion.objects.create(
            platform='ios',
            version='1.0.0',
            build_number=100,
            status=VersionStatus.DEPRECATED.value,
            update_type=UpdateType.OPTIONAL.value
        )
        
        self.ios_v2 = AppVersion.objects.create(
            platform='ios',
            version='1.1.0',
            build_number=110,
            status=VersionStatus.ACTIVE.value,
            update_type=UpdateType.OPTIONAL.value,
            min_supported_version='1.0.0'
        )
        
        self.ios_v3 = AppVersion.objects.create(
            platform='ios',
            version='1.2.0',
            build_number=120,
            status=VersionStatus.ACTIVE.value,
            update_type=UpdateType.REQUIRED.value,
            min_supported_version='1.1.0',
            features=['dark_mode', 'biometric_auth'],
            changelog='- Added dark mode\n- Biometric authentication\n- Bug fixes',
            ios_store_url='https://apps.apple.com/app/id123456789'
        )
        
        self.android_v1 = AppVersion.objects.create(
            platform='android',
            version='1.0.0',
            version_code=100,
            status=VersionStatus.ACTIVE.value,
            update_type=UpdateType.OPTIONAL.value
        )
        
        # Create test feature flags
        self.social_login_flag = FeatureFlag.objects.create(
            name='social_login',
            description='Enable social authentication',
            enabled=True,
            rollout_percentage=50
        )
        
        self.dark_mode_flag = FeatureFlag.objects.create(
            name='dark_mode',
            description='Enable dark mode',
            enabled=True,
            rollout_percentage=100,
            min_ios_version='1.2.0',
            min_android_version='1.1.0',
            enabled_for_staff=True
        )
    
    def test_check_version_latest(self):
        """Test checking version when on latest"""
        response = self.client.post(
            '/api/channels/version/check/',
            {
                'platform': 'ios',
                'version': '1.2.0',
                'build_number': 120
            },
            format='json',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertFalse(data['update_required'])
        self.assertFalse(data['update_available'])
        self.assertEqual(data['current_version'], '1.2.0')
        self.assertEqual(data['latest_version'], '1.2.0')
        self.assertIn('checked_at', data)
    
    def test_check_version_update_available(self):
        """Test checking version when update is available"""
        response = self.client.post(
            '/api/channels/version/check/',
            {
                'platform': 'ios',
                'version': '1.1.0',
                'build_number': 110
            },
            format='json',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertTrue(data['update_required'])  # Because latest has REQUIRED update type
        self.assertTrue(data['update_available'])
        self.assertEqual(data['update_type'], UpdateType.REQUIRED)
        self.assertEqual(data['current_version'], '1.1.0')
        self.assertEqual(data['latest_version'], '1.2.0')
        self.assertIn('changelog', data)
        self.assertIn('features', data)
        self.assertIn('store_url', data)
    
    def test_check_version_forced_update(self):
        """Test checking version when forced update is required"""
        # Mark old version as unsupported
        self.ios_v1.status = VersionStatus.UNSUPPORTED
        self.ios_v1.save()
        
        response = self.client.post(
            '/api/channels/version/check/',
            {
                'platform': 'ios',
                'version': '1.0.0',
                'build_number': 100
            },
            format='json',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertTrue(data['update_required'])
        self.assertEqual(data['update_type'], UpdateType.FORCED)
        self.assertIn('message', data)
    
    def test_check_version_unknown(self):
        """Test checking unknown version"""
        response = self.client.post(
            '/api/channels/version/check/',
            {
                'platform': 'ios',
                'version': '0.9.0',
                'build_number': 90
            },
            format='json',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertTrue(data['update_required'])
        self.assertEqual(data['update_type'], UpdateType.FORCED)
        self.assertIn('not recognized', data['message'])
    
    def test_check_version_invalid_platform(self):
        """Test checking version with invalid platform"""
        response = self.client.post(
            '/api/channels/version/check/',
            {
                'platform': 'windows',
                'version': '1.0.0'
            },
            format='json',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        data = response.json()
        self.assertIn('error', data)
        self.assertIn('Invalid platform', data['error'])
    
    def test_check_version_missing_params(self):
        """Test checking version with missing parameters"""
        response = self.client.post(
            '/api/channels/version/check/',
            {},
            format='json',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        data = response.json()
        self.assertIn('error', data)
    
    def test_get_latest_version(self):
        """Test getting latest version info"""
        response = self.client.get('/api/channels/version/latest/?platform=ios', HTTP_X_TENANT_ID='default')
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertEqual(data['platform'], 'ios')
        self.assertEqual(data['version'], '1.2.0')
        self.assertEqual(data['build_number'], 120)
        self.assertIn('features', data)
        self.assertIn('changelog', data)
        self.assertIn('store_url', data)
        self.assertIn('released_at', data)
    
    def test_get_latest_version_no_platform(self):
        """Test getting latest version without platform"""
        response = self.client.get('/api/channels/version/latest/', HTTP_X_TENANT_ID='default')
        
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        data = response.json()
        self.assertIn('error', data)
    
    def test_get_supported_versions(self):
        """Test getting all supported versions"""
        response = self.client.get('/api/channels/version/supported/?platform=ios', HTTP_X_TENANT_ID='default')
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertIn('versions', data)
        self.assertIn('count', data)
        self.assertEqual(data['count'], 3)  # All 3 iOS versions
        
        # Check version order (newest first)
        versions = data['versions']
        self.assertEqual(versions[0]['version'], '1.2.0')
        self.assertEqual(versions[1]['version'], '1.1.0')
        self.assertEqual(versions[2]['version'], '1.0.0')
    
    def test_get_supported_versions_all_platforms(self):
        """Test getting supported versions for all platforms"""
        response = self.client.get('/api/channels/version/supported/', HTTP_X_TENANT_ID='default')
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertIn('versions', data)
        self.assertEqual(data['count'], 4)  # 3 iOS + 1 Android
    
    def test_get_feature_flags_authenticated(self):
        """Test getting feature flags for authenticated user"""
        self.client.force_authenticate(user=self.user)
        
        response = self.client.get(
            '/api/channels/features/?platform=ios&version=1.2.0',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertIn('features', data)
        self.assertIn('user_id', data)
        self.assertEqual(data['platform'], 'ios')
        self.assertEqual(data['version'], '1.2.0')
        
        # Check feature flags
        features = data['features']
        self.assertIn('dark_mode', features)
        self.assertTrue(features['dark_mode'])  # Should be enabled for v1.2.0
        self.assertIn('social_login', features)
    
    def test_get_feature_flags_version_requirement(self):
        """Test feature flags with version requirements"""
        self.client.force_authenticate(user=self.user)
        
        # Check with older version
        response = self.client.get(
            '/api/channels/features/?platform=ios&version=1.1.0',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        features = data['features']
        
        # Dark mode should be disabled for v1.1.0
        self.assertIn('dark_mode', features)
        self.assertFalse(features['dark_mode'])
    
    def test_get_feature_flags_unauthenticated(self):
        """Test getting feature flags without authentication"""
        response = self.client.get(
            '/api/channels/features/?platform=ios&version=1.2.0',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
    
    def test_check_version_with_feature_flags(self):
        """Test version check includes feature flags for authenticated user"""
        self.client.force_authenticate(user=self.user)
        
        response = self.client.post(
            '/api/channels/version/check/',
            {
                'platform': 'ios',
                'version': '1.2.0',
                'build_number': 120
            },
            format='json',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        self.assertIn('features', data)
        self.assertIn('dark_mode', data['features'])
        self.assertIn('social_login', data['features'])
    
    def test_feature_flag_rollout_percentage(self):
        """Test feature flag rollout percentage"""
        self.client.force_authenticate(user=self.user)
        
        # Social login has 50% rollout
        response = self.client.get(
            '/api/channels/features/?platform=ios&version=1.2.0',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        features = data['features']
        
        # Should be deterministic for same user
        self.assertIn('social_login', features)
        self.assertIsInstance(features['social_login'], bool)
    
    def test_feature_flag_staff_override(self):
        """Test feature flag staff override"""
        self.user.is_staff = True
        self.user.save()
        self.client.force_authenticate(user=self.user)
        
        # Disable a feature but keep it enabled for staff
        self.dark_mode_flag.enabled = False
        self.dark_mode_flag.enabled_for_staff = True
        self.dark_mode_flag.save()
        
        response = self.client.get(
            '/api/channels/features/?platform=ios&version=1.2.0',
            HTTP_X_TENANT_ID='default'
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        features = data['features']
        
        # Should still be enabled for staff
        self.assertIn('dark_mode', features)
        self.assertTrue(features['dark_mode'])
