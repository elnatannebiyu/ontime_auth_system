import json
from django.test import TestCase, Client
from django.contrib.auth import get_user_model
from django.core.cache import cache
from unittest.mock import patch, MagicMock
from tenants.models import Tenant

User = get_user_model()


class DynamicFormsAPITestCase(TestCase):
    def setUp(self):
        """Set up test data"""
        # Clear cache to avoid rate limiting issues
        cache.clear()
        
        # Create test tenant
        self.tenant = Tenant.objects.create(
            name="Test Tenant",
            slug="default",
            active=True
        )
        
        # Create test user
        self.user = User.objects.create_user(
            username='testuser',
            email='test@example.com',
            password='TestPass123!'
        )
        
        self.client = Client()
        self.headers = {'HTTP_X_TENANT_ID': 'default'}
    
    def test_get_login_form_schema(self):
        """Test getting login form schema"""
        response = self.client.get(
            '/api/forms/schema/',
            {'action': 'login'},
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        # Check form structure
        self.assertEqual(data['action'], 'login')
        self.assertEqual(data['form_id'], 'login_form')
        self.assertIn('fields', data)
        self.assertIn('submit_button', data)
        self.assertIn('social_auth', data)
        
        # Check fields
        fields = data['fields']
        field_names = [f['name'] for f in fields]
        self.assertIn('username', field_names)
        self.assertIn('password', field_names)
        
        # Check social auth
        self.assertTrue(data['social_auth']['enabled'])
        self.assertIn('google', data['social_auth']['providers'])
    
    def test_get_register_form_schema(self):
        """Test getting registration form schema"""
        response = self.client.get(
            '/api/forms/schema/',
            {'action': 'register'},
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data['action'], 'register')
        self.assertEqual(data['form_id'], 'register_form')
        
        # Check required fields
        fields = data['fields']
        field_names = [f['name'] for f in fields]
        self.assertIn('email', field_names)
        self.assertIn('username', field_names)
        self.assertIn('password', field_names)
        self.assertIn('confirm_password', field_names)
        
        # Check validation rules
        email_field = next(f for f in fields if f['name'] == 'email')
        validation_rules = [r['rule'] for r in email_field['validation']]
        self.assertIn('required', validation_rules)
        self.assertIn('email', validation_rules)
        self.assertIn('unique', validation_rules)
    
    def test_get_otp_verification_form_schema(self):
        """Test getting OTP verification form schema"""
        response = self.client.get(
            '/api/forms/schema/',
            {'action': 'verify_otp'},
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data['action'], 'verify_otp')
        fields = data['fields']
        field_names = [f['name'] for f in fields]
        self.assertIn('identifier', field_names)
        self.assertIn('otp_code', field_names)
    
    def test_get_reset_password_form_schema(self):
        """Test getting reset password form schema"""
        response = self.client.get(
            '/api/forms/schema/',
            {'action': 'reset_password'},
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        self.assertEqual(data['action'], 'reset_password')
        fields = data['fields']
        field_names = [f['name'] for f in fields]
        self.assertIn('email', field_names)
    
    def test_form_schema_with_context(self):
        """Test form schema with context modifications"""
        response = self.client.get(
            '/api/forms/schema/',
            {
                'action': 'login',
                'context': json.dumps({'disable_social': True})
            },
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        # Social auth should be disabled
        self.assertFalse(data['social_auth']['enabled'])
    
    def test_invalid_action(self):
        """Test invalid form action"""
        response = self.client.get(
            '/api/forms/schema/',
            {'action': 'invalid_action'},
            **self.headers
        )
        
        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertIn('error', data)
    
    def test_validate_field_required(self):
        """Test field validation - required rule"""
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'email',
                'value': '',
                'rules': [{'rule': 'required', 'message': 'Email is required'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['valid'])
        self.assertIn('Email is required', data['errors'])
    
    def test_validate_field_email(self):
        """Test field validation - email format"""
        # Invalid email
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'email',
                'value': 'invalid-email',
                'rules': [{'rule': 'email'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['valid'])
        
        # Valid email
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'email',
                'value': 'valid@example.com',
                'rules': [{'rule': 'email'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['valid'])
    
    def test_validate_field_unique(self):
        """Test field validation - unique constraint"""
        # Email already exists
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'email',
                'value': 'test@example.com',  # Already exists in setUp
                'rules': [{'rule': 'unique', 'model': 'User', 'field': 'email'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['valid'])
        
        # New email
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'email',
                'value': 'new@example.com',
                'rules': [{'rule': 'unique', 'model': 'User', 'field': 'email'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['valid'])
    
    def test_validate_field_pattern(self):
        """Test field validation - pattern matching"""
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'username',
                'value': 'user@123',  # Contains invalid character @
                'rules': [{'rule': 'pattern', 'value': '^[a-zA-Z0-9_]+$'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['valid'])
        
        # Valid username
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'username',
                'value': 'user_123',
                'rules': [{'rule': 'pattern', 'value': '^[a-zA-Z0-9_]+$'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['valid'])
    
    def test_validate_field_strong_password(self):
        """Test field validation - strong password"""
        # Weak password
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'password',
                'value': 'weak',
                'rules': [{'rule': 'strong_password'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertFalse(data['valid'])
        self.assertTrue(len(data['errors']) > 0)
        
        # Strong password
        response = self.client.post(
            '/api/forms/validate/',
            json.dumps({
                'field': 'password',
                'value': 'Strong@Pass123',
                'rules': [{'rule': 'strong_password'}]
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        self.assertTrue(data['valid'])
    
    @patch('accounts.views.TokenObtainPairWithCookieView.as_view')
    def test_submit_login_form(self, mock_login_view):
        """Test submitting login form"""
        # Mock the login view response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.data = {'access': 'token', 'user': {'id': 1}}
        mock_login_view.return_value.return_value = mock_response
        
        response = self.client.post(
            '/api/forms/submit/',
            json.dumps({
                'action': 'login',
                'data': {
                    'username': 'testuser',
                    'password': 'TestPass123!'
                }
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
    
    def test_submit_registration_form(self):
        """Test submitting registration form"""
        response = self.client.post(
            '/api/forms/submit/',
            json.dumps({
                'action': 'register',
                'data': {
                    'email': 'newuser@example.com',
                    'username': 'newuser',
                    'password': 'NewPass123!',
                    'confirm_password': 'NewPass123!',
                    'first_name': 'New',
                    'last_name': 'User'
                }
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 201)
        data = response.json()
        self.assertIn('message', data)
        
        # Verify user was created
        self.assertTrue(
            User.objects.filter(username='newuser').exists()
        )
    
    def test_submit_registration_password_mismatch(self):
        """Test registration with password mismatch"""
        response = self.client.post(
            '/api/forms/submit/',
            json.dumps({
                'action': 'register',
                'data': {
                    'email': 'newuser@example.com',
                    'username': 'newuser',
                    'password': 'NewPass123!',
                    'confirm_password': 'DifferentPass123!'
                }
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertIn('error', data)
    
    def test_submit_invalid_action(self):
        """Test submitting form with invalid action"""
        response = self.client.post(
            '/api/forms/submit/',
            json.dumps({
                'action': 'invalid_action',
                'data': {}
            }),
            content_type='application/json',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 400)
        data = response.json()
        self.assertIn('error', data)
    
    def test_get_form_config(self):
        """Test getting form configuration"""
        response = self.client.get(
            '/api/forms/config/',
            **self.headers
        )
        
        self.assertEqual(response.status_code, 200)
        data = response.json()
        
        # Check configuration structure
        self.assertIn('username', data)
        self.assertIn('password', data)
        self.assertIn('features', data)
        self.assertIn('otp', data)
        
        # Check specific values
        self.assertEqual(data['username']['min_length'], 3)
        self.assertEqual(data['password']['min_length'], 8)
        self.assertTrue(data['features']['email_verification'])
        self.assertEqual(data['otp']['length'], 6)
