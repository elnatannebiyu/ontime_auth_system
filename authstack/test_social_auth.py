import json
from django.test import TestCase
from django.contrib.auth import get_user_model
from unittest.mock import patch, MagicMock
from rest_framework import status
from accounts.models import SocialAccount
from tenants.models import Tenant, TenantDomain
from django.core.cache import cache

User = get_user_model()


class SocialAuthTestCase(TestCase):
    def setUp(self):
        from django.test import Client
        self.client = Client()
        
        # Clear cache to reset rate limiting
        cache.clear()
        
        # Create a test tenant
        self.tenant = Tenant.objects.create(
            slug='test-tenant',
            name='Test Tenant',
            active=True
        )
        # Create a domain for the tenant
        TenantDomain.objects.create(
            tenant=self.tenant,
            domain="testserver"
        )
        
        # Set tenant header for all requests (use slug, not id)
        self.headers = {'HTTP_X_TENANT_ID': self.tenant.slug}
        
        # Mock token data
        self.google_token_data = {
            'provider_id': 'google_user_123',
            'email': 'test@example.com',
            'email_verified': True,
            'name': 'Test User',
            'given_name': 'Test',
            'family_name': 'User',
        }
        
        self.apple_token_data = {
            'provider_id': 'apple_user_456',
            'email': 'apple@example.com',
            'email_verified': True
        }
    
    @patch('accounts.social_auth.SocialAuthService.verify_google_token')
    def test_social_login_google_new_user(self, mock_verify):
        """Test Google login creates new user"""
        mock_verify.return_value = (True, self.google_token_data)
        
        response = self.client.post(
            '/api/social/login/',
            data=json.dumps({
                'provider': 'google',
                'token': 'fake_google_token'
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        data = response.json()
        
        # Check response has tokens
        self.assertIn('access', data)
        self.assertIn('refresh', data)
        self.assertIn('user', data)
        
        # Check user was created
        user = User.objects.get(email='test@example.com')
        self.assertEqual(user.first_name, 'Test')
        self.assertEqual(user.last_name, 'User')
        
        # Check social account was created
        social_account = SocialAccount.objects.get(user=user)
        self.assertEqual(social_account.provider, 'google')
        self.assertEqual(social_account.provider_id, 'google_user_123')
        self.assertEqual(social_account.email, 'test@example.com')
        
        # Check refresh token cookie was set
        self.assertIn('refresh_token', response.cookies)
    
    @patch('accounts.social_auth.SocialAuthService.verify_google_token')
    def test_social_login_google_existing_user(self, mock_verify):
        """Test Google login with existing user"""
        # Create existing user
        user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        
        mock_verify.return_value = (True, self.google_token_data)
        
        response = self.client.post(
            '/api/social/login/',
            data=json.dumps({
                'provider': 'google',
                'token': 'fake_google_token'
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        
        # Check social account was linked to existing user
        social_account = SocialAccount.objects.get(provider='google', provider_id='google_user_123')
        self.assertEqual(social_account.user, user)
    
    @patch('accounts.social_auth.SocialAuthService.verify_apple_token')
    def test_social_login_apple(self, mock_verify):
        """Test Apple login"""
        mock_verify.return_value = (True, self.apple_token_data)
        
        response = self.client.post(
            '/api/social/login/',
            data=json.dumps({
                'provider': 'apple',
                'token': 'fake_apple_token',
                'nonce': 'test_nonce'
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        
        # Check user and social account were created
        user = User.objects.get(email='apple@example.com')
        social_account = SocialAccount.objects.get(user=user)
        self.assertEqual(social_account.provider, 'apple')
        self.assertEqual(social_account.provider_id, 'apple_user_456')
    
    def test_social_login_invalid_provider(self):
        """Test login with invalid provider"""
        response = self.client.post(
            '/api/social/login/',
            data=json.dumps({
                'provider': 'invalid',
                'token': 'fake_token'
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Unsupported provider', response.json()['error'])
    
    @patch('accounts.social_auth.SocialAuthService.verify_google_token')
    def test_social_login_invalid_token(self, mock_verify):
        """Test login with invalid token"""
        mock_verify.return_value = (False, {'error': 'Invalid token'})
        
        response = self.client.post(
            '/api/social/login/',
            data=json.dumps({
                'provider': 'google',
                'token': 'invalid_token'
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_401_UNAUTHORIZED)
        self.assertIn('Invalid token', response.json()['error'])
    
    @patch('accounts.social_auth.SocialAuthService.verify_google_token')
    def test_link_social_account(self, mock_verify):
        """Test linking social account to existing user"""
        # Create user and login
        user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        
        login_response = self.client.post(
            '/api/token/',
            data=json.dumps({
                'username': 'testuser',
                'password': 'testpass123'
            }),
            content_type='application/json',
            **self.headers
        )
        
        access_token = login_response.json()['access']
        
        # Link social account
        mock_verify.return_value = (True, self.google_token_data)
        
        response = self.client.post(
            '/api/social/link/',
            data=json.dumps({
                'provider': 'google',
                'token': 'fake_google_token'
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {access_token}',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        
        # Check social account was linked
        social_account = SocialAccount.objects.get(user=user)
        self.assertEqual(social_account.provider, 'google')
        self.assertEqual(social_account.provider_id, 'google_user_123')
    
    @patch('accounts.social_auth.SocialAuthService.verify_google_token')
    def test_link_duplicate_social_account(self, mock_verify):
        """Test linking already linked social account"""
        # Create user and social account
        user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='testpass123'
        )
        
        SocialAccount.objects.create(
            user=user,
            provider='google',
            provider_id='google_user_123',
            email='test@example.com'
        )
        
        # Login
        login_response = self.client.post(
            '/api/token/',
            data=json.dumps({
                'username': 'testuser',
                'password': 'testpass123'
            }),
            content_type='application/json',
            **self.headers
        )
        
        access_token = login_response.json()['access']
        
        # Try to link same account
        mock_verify.return_value = (True, self.google_token_data)
        
        response = self.client.post(
            '/api/social/link/',
            data=json.dumps({
                'provider': 'google',
                'token': 'fake_google_token'
            }),
            content_type='application/json',
            HTTP_AUTHORIZATION=f'Bearer {access_token}',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        self.assertIn('already linked', response.json()['message'])
    
    def test_unlink_social_account(self):
        """Test unlinking social account"""
        # Create user with password and social account
        user = User.objects.create_user(
            username='testuser',
            email='user@example.com',
            password='testpass123'
        )
        
        SocialAccount.objects.create(
            user=user,
            provider='google',
            provider_id='google_user_123',
            email='test@example.com'
        )
        
        # Login
        login_response = self.client.post(
            '/api/token/',
            data=json.dumps({'username': 'testuser', 'password': 'testpass123'}),
            content_type='application/json',
            **self.headers
        )
        access_token = login_response.json()['access']
        
        # Unlink social account
        response = self.client.delete(
            '/api/social/unlink/google/',
            HTTP_AUTHORIZATION=f'Bearer {access_token}',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_200_OK)
        
        # Check social account was deleted
        self.assertFalse(SocialAccount.objects.filter(user=user, provider='google').exists())
    
    def test_unlink_last_auth_method(self):
        """Test cannot unlink last authentication method"""
        # Create user without password (social login only)
        user = User.objects.create_user(
            username='socialuser',
            email='social@example.com'
        )
        user.set_unusable_password()
        user.save()
        
        SocialAccount.objects.create(
            user=user,
            provider='google',
            provider_id='google_user_123',
            email='social@example.com'
        )
        
        # Create a session for the user (simulate social login)
        from user_sessions.models import Session
        session, refresh_token = Session.create_session(
            user=user,
            request=MagicMock(
                META={'REMOTE_ADDR': '127.0.0.1', 'HTTP_USER_AGENT': 'test'}
            )
        )
        
        # Generate access token
        from accounts.jwt_auth import CustomTokenObtainPairSerializer
        serializer = CustomTokenObtainPairSerializer()
        token = serializer.get_token(user)
        access_token = str(token.access_token)
        
        # Try to unlink the only auth method
        response = self.client.delete(
            '/api/social/unlink/google/',
            HTTP_AUTHORIZATION=f'Bearer {access_token}',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_400_BAD_REQUEST)
        self.assertIn('Cannot unlink', response.json()['error'])
    
    @patch('accounts.social_auth.SocialAuthService.verify_google_token')
    def test_social_login_banned_user(self, mock_verify):
        """Test social login with banned user"""
        # Create banned user with social account
        user = User.objects.create_user(
            username='banneduser',
            email='banned@example.com',
            is_active=False
        )
        
        SocialAccount.objects.create(
            user=user,
            provider='google',
            provider_id='google_user_123',
            email='banned@example.com'
        )
        
        mock_verify.return_value = (True, self.google_token_data)
        
        response = self.client.post(
            '/api/social/login/',
            data=json.dumps({
                'provider': 'google',
                'token': 'fake_google_token'
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, status.HTTP_403_FORBIDDEN)
        self.assertIn('Account is disabled', response.json()['error'])
