import json
from django.test import TestCase
from rest_framework.test import APIClient
from django.contrib.auth import get_user_model
from django.utils import timezone
from otp_auth.models import OTPRequest
from tenants.models import Tenant
from unittest.mock import patch, MagicMock
from django.core.cache import cache
import uuid

User = get_user_model()

class OTPAuthenticationTestCase(TestCase):
    def setUp(self):
        # Create default tenant
        self.tenant, _ = Tenant.objects.get_or_create(
            slug='default',
            defaults={'name': 'Default Tenant', 'active': True}
        )
        
        self.client = APIClient()
        self.client.credentials(HTTP_X_TENANT_ID='default')
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='TestPass123!'
        )
        
        # Clear any existing OTP requests to avoid rate limiting
        OTPRequest.objects.all().delete()
        
        # Clear cache to reset rate limiting
        cache.clear()
    
    def test_request_otp_email(self):
        """Test requesting OTP via email"""
        response = self.client.post('/api/auth/otp/request/', {
            'destination': 'test@example.com',
            'purpose': 'login'
        })
        
        self.assertEqual(response.status_code, 200)
        self.assertIn('otp_id', response.json())
        self.assertIn('destination_masked', response.json())
        self.assertIn('expires_in', response.json())
        
        # Check OTP was created
        otp = OTPRequest.objects.get(destination='test@example.com')
        self.assertEqual(otp.otp_type, 'email')
        self.assertEqual(otp.purpose, 'login')
        self.assertEqual(otp.user, self.user)
        self.assertFalse(otp.is_verified)
        # OTP code should be '123456' in DEBUG mode
        self.assertEqual(otp.otp_code, '123456')
    
    def test_request_otp_phone(self):
        """Test requesting OTP via phone"""
        response = self.client.post('/api/auth/otp/request/', {
            'destination': '+1234567890',
            'purpose': 'login'
        })
        
        # Should fail as user doesn't have this phone
        self.assertEqual(response.status_code, 404)
        self.assertEqual(response.json()['code'], 'USER_NOT_FOUND')
    
    def test_request_otp_invalid_destination(self):
        """Test requesting OTP with invalid destination"""
        response = self.client.post('/api/auth/otp/request/', {
            'destination': 'invalid',
            'purpose': 'login'
        })
        
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['code'], 'VALIDATION_ERROR')
    
    def test_verify_otp_success(self):
        """Test successful OTP verification and login"""
        # Request OTP first
        response = self.client.post('/api/auth/otp/request/', {
            'destination': 'test@example.com',
            'purpose': 'login'
        })
        self.assertEqual(response.status_code, 200)
        otp_id = response.json()['otp_id']
        
        # Verify OTP
        response = self.client.post('/api/auth/otp/verify/', {
            'otp_id': otp_id,
            'otp_code': '123456'  # Fixed in DEBUG mode
        })
        
        # Debug the error if it fails
        if response.status_code != 200:
            print(f"Verify OTP failed: {response.status_code}")
            print(f"Response: {response.json()}")
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertIn('access', data)
        self.assertIn('session_id', data)
        self.assertIn('user', data)
        self.assertEqual(data['user']['email'], 'test@example.com')
        
        # Check refresh token cookie
        self.assertIn('refresh_token', response.cookies)
    
    def test_verify_otp_wrong_code(self):
        """Test OTP verification with wrong code"""
        # Request OTP
        response = self.client.post('/api/auth/otp/request/', {
            'destination': 'test@example.com',
            'purpose': 'login'
        })
        
        # Debug if request fails
        if response.status_code != 200:
            print(f"OTP request failed: {response.status_code}")
            print(f"Response: {response.json()}")
            
        self.assertEqual(response.status_code, 200)
        otp_id = response.json()['otp_id']
        
        # Verify with wrong code
        response = self.client.post('/api/auth/otp/verify/', {
            'otp_id': otp_id,
            'otp_code': '999999'
        })
        
        self.assertEqual(response.status_code, 400)
        self.assertEqual(response.json()['code'], 'INVALID_OTP')
    
    def test_otp_max_attempts(self):
        """Test OTP max attempts limit"""
        # Request OTP
        response = self.client.post('/api/auth/otp/request/', {
            'destination': 'test@example.com',
            'purpose': 'login'
        })
        otp_id = response.json()['otp_id']
        
        # Try wrong code 3 times
        for i in range(3):
            response = self.client.post('/api/auth/otp/verify/', {
                'otp_id': otp_id,
                'otp_code': '999999'
            })
            self.assertEqual(response.status_code, 400)
        
        # 4th attempt should fail even with correct code
        response = self.client.post('/api/auth/otp/verify/', {
            'otp_id': otp_id,
            'otp_code': '123456'
        })
        self.assertEqual(response.status_code, 400)
        self.assertIn('Too many attempts', response.json()['message'])
    
    def test_otp_expiry(self):
        """Test OTP expiry"""
        # Request OTP
        response = self.client.post('/api/auth/otp/request/', {
            'destination': 'test@example.com',
            'purpose': 'login'
        })
        otp_id = response.json()['otp_id']
        
        # Manually expire the OTP
        otp = OTPRequest.objects.get(id=otp_id)
        otp.expires_at = timezone.now() - timezone.timedelta(minutes=1)
        otp.save()
        
        # Try to verify expired OTP
        response = self.client.post('/api/auth/otp/verify/', {
            'otp_id': otp_id,
            'otp_code': '123456'
        })
        
        self.assertEqual(response.status_code, 400)
        self.assertIn('expired', response.json()['message'].lower())
    
    def test_otp_rate_limiting(self):
        """Test OTP request rate limiting"""
        destination = 'test@example.com'
        
        # Create 5 OTP requests (max allowed per hour)
        for i in range(5):
            OTPRequest.objects.create(
                otp_type='email',
                destination=destination,
                purpose='login',
                otp_code='123456',
                otp_hash='hash',
                expires_at=timezone.now() + timezone.timedelta(minutes=10),
                created_at=timezone.now() - timezone.timedelta(minutes=i)
            )
        
        # 6th request should be rate limited
        response = self.client.post('/api/auth/otp/request/', {
            'destination': destination,
            'purpose': 'login'
        })
        
        self.assertEqual(response.status_code, 429)
        self.assertEqual(response.json()['code'], 'RATE_LIMIT')
    
    def test_otp_registration_flow(self):
        """Test OTP for registration purpose"""
        new_email = 'newuser@example.com'
        
        # Request OTP for registration
        response = self.client.post('/api/auth/otp/request/', {
            'destination': new_email,
            'purpose': 'register'
        })
        
        self.assertEqual(response.status_code, 200)
        otp_id = response.json()['otp_id']
        
        # Verify OTP
        response = self.client.post('/api/auth/otp/verify/', {
            'otp_id': otp_id,
            'otp_code': '123456'
        })
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertEqual(data['message'], 'OTP verified')
        self.assertEqual(data['verified_destination'], new_email)
        self.assertIn('verification_token', data)
    
    def test_destination_masking(self):
        """Test email/phone masking in responses"""
        response = self.client.post('/api/auth/otp/request/', {
            'destination': 'test@example.com',
            'purpose': 'login'
        })
        
        data = response.json()
        self.assertEqual(data['destination_masked'], 't**t@example.com')


if __name__ == '__main__':
    import django
    django.setup()
    import unittest
    unittest.main()
