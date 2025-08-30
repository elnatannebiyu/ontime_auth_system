# Part 6: Dynamic Forms API

## Overview
Implement backend-driven dynamic authentication forms with custom validation and UI hints.

## 6.1 Form Schema Models

```python
# accounts/form_schemas.py
from typing import Dict, List, Any
from enum import Enum

class FieldType(str, Enum):
    TEXT = "text"
    EMAIL = "email"
    PASSWORD = "password"
    PHONE = "phone"
    SELECT = "select"
    CHECKBOX = "checkbox"
    DATE = "date"
    OTP = "otp"
    HIDDEN = "hidden"

class ValidationRule(str, Enum):
    REQUIRED = "required"
    MIN_LENGTH = "min_length"
    MAX_LENGTH = "max_length"
    PATTERN = "pattern"
    EMAIL = "email"
    PHONE = "phone"
    MATCH_FIELD = "match_field"
    UNIQUE = "unique"
    STRONG_PASSWORD = "strong_password"

class FormAction(str, Enum):
    LOGIN = "login"
    REGISTER = "register"
    RESET_PASSWORD = "reset_password"
    VERIFY_EMAIL = "verify_email"
    VERIFY_PHONE = "verify_phone"
    UPDATE_PROFILE = "update_profile"

class DynamicFormSchema:
    """Define dynamic form schemas for different auth flows"""
    
    @classmethod
    def get_login_schema(cls) -> Dict[str, Any]:
        """Get login form schema"""
        return {
            "form_id": "login_form",
            "title": "Sign In",
            "description": "Enter your credentials to continue",
            "action": FormAction.LOGIN,
            "submit_button": {
                "text": "Sign In",
                "loading_text": "Signing in..."
            },
            "fields": [
                {
                    "name": "username",
                    "type": FieldType.TEXT,
                    "label": "Email or Username",
                    "placeholder": "Enter email or username",
                    "icon": "person",
                    "required": True,
                    "autofocus": True,
                    "validation": [
                        {"rule": ValidationRule.REQUIRED, "message": "Username is required"},
                        {"rule": ValidationRule.MIN_LENGTH, "value": 3, "message": "Minimum 3 characters"}
                    ]
                },
                {
                    "name": "password",
                    "type": FieldType.PASSWORD,
                    "label": "Password",
                    "placeholder": "Enter password",
                    "icon": "lock",
                    "required": True,
                    "show_toggle": True,
                    "validation": [
                        {"rule": ValidationRule.REQUIRED, "message": "Password is required"}
                    ]
                },
                {
                    "name": "remember_me",
                    "type": FieldType.CHECKBOX,
                    "label": "Remember me",
                    "default_value": False
                }
            ],
            "links": [
                {"text": "Forgot password?", "action": "forgot_password", "align": "right"},
                {"text": "Don't have an account? Sign up", "action": "register", "align": "center"}
            ],
            "social_auth": {
                "enabled": True,
                "providers": ["google", "apple", "facebook"],
                "divider_text": "Or continue with"
            }
        }
    
    @classmethod
    def get_register_schema(cls, require_phone: bool = False) -> Dict[str, Any]:
        """Get registration form schema"""
        fields = [
            {
                "name": "email",
                "type": FieldType.EMAIL,
                "label": "Email Address",
                "placeholder": "your@email.com",
                "icon": "email",
                "required": True,
                "autofocus": True,
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Email is required"},
                    {"rule": ValidationRule.EMAIL, "message": "Invalid email format"},
                    {"rule": ValidationRule.UNIQUE, "model": "User", "field": "email", "message": "Email already registered"}
                ]
            },
            {
                "name": "username",
                "type": FieldType.TEXT,
                "label": "Username",
                "placeholder": "Choose a username",
                "icon": "person",
                "required": True,
                "hint": "3-20 characters, letters, numbers, and underscores only",
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Username is required"},
                    {"rule": ValidationRule.MIN_LENGTH, "value": 3, "message": "Minimum 3 characters"},
                    {"rule": ValidationRule.MAX_LENGTH, "value": 20, "message": "Maximum 20 characters"},
                    {"rule": ValidationRule.PATTERN, "value": "^[a-zA-Z0-9_]+$", "message": "Only letters, numbers, and underscores"},
                    {"rule": ValidationRule.UNIQUE, "model": "User", "field": "username", "message": "Username taken"}
                ]
            }
        ]
        
        if require_phone:
            fields.append({
                "name": "phone",
                "type": FieldType.PHONE,
                "label": "Phone Number",
                "placeholder": "+1234567890",
                "icon": "phone",
                "required": True,
                "country_code": "US",
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Phone number is required"},
                    {"rule": ValidationRule.PHONE, "message": "Invalid phone number"},
                    {"rule": ValidationRule.UNIQUE, "model": "User", "field": "phone_e164", "message": "Phone already registered"}
                ]
            })
        
        fields.extend([
            {
                "name": "password",
                "type": FieldType.PASSWORD,
                "label": "Password",
                "placeholder": "Create a strong password",
                "icon": "lock",
                "required": True,
                "show_toggle": True,
                "show_strength": True,
                "hint": "8+ characters with uppercase, lowercase, number, and symbol",
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Password is required"},
                    {"rule": ValidationRule.MIN_LENGTH, "value": 8, "message": "Minimum 8 characters"},
                    {"rule": ValidationRule.STRONG_PASSWORD, "message": "Password too weak"}
                ]
            },
            {
                "name": "confirm_password",
                "type": FieldType.PASSWORD,
                "label": "Confirm Password",
                "placeholder": "Re-enter password",
                "icon": "lock_outline",
                "required": True,
                "show_toggle": True,
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "Please confirm password"},
                    {"rule": ValidationRule.MATCH_FIELD, "field": "password", "message": "Passwords don't match"}
                ]
            },
            {
                "name": "terms",
                "type": FieldType.CHECKBOX,
                "label": "I agree to the Terms of Service and Privacy Policy",
                "required": True,
                "validation": [
                    {"rule": ValidationRule.REQUIRED, "message": "You must accept the terms"}
                ]
            }
        ])
        
        return {
            "form_id": "register_form",
            "title": "Create Account",
            "description": "Join us today",
            "action": FormAction.REGISTER,
            "submit_button": {
                "text": "Create Account",
                "loading_text": "Creating account..."
            },
            "fields": fields,
            "links": [
                {"text": "Already have an account? Sign in", "action": "login", "align": "center"}
            ],
            "social_auth": {
                "enabled": True,
                "providers": ["google", "apple", "facebook"],
                "divider_text": "Or sign up with"
            }
        }
    
    @classmethod
    def get_otp_verification_schema(cls, destination_type: str = "email") -> Dict[str, Any]:
        """Get OTP verification form schema"""
        return {
            "form_id": "otp_verification",
            "title": f"Verify Your {destination_type.title()}",
            "description": f"We've sent a code to your {destination_type}",
            "action": FormAction.VERIFY_EMAIL if destination_type == "email" else FormAction.VERIFY_PHONE,
            "submit_button": {
                "text": "Verify",
                "loading_text": "Verifying..."
            },
            "fields": [
                {
                    "name": "otp_code",
                    "type": FieldType.OTP,
                    "label": "Verification Code",
                    "placeholder": "000000",
                    "length": 6,
                    "numeric_only": True,
                    "autofocus": True,
                    "auto_submit": True,
                    "validation": [
                        {"rule": ValidationRule.REQUIRED, "message": "Code is required"},
                        {"rule": ValidationRule.MIN_LENGTH, "value": 6, "message": "Enter 6 digits"},
                        {"rule": ValidationRule.MAX_LENGTH, "value": 6, "message": "Enter 6 digits"}
                    ]
                }
            ],
            "resend": {
                "enabled": True,
                "cooldown": 60,
                "text": "Didn't receive code?",
                "button_text": "Resend Code"
            },
            "timer": {
                "enabled": True,
                "duration": 300,
                "message": "Code expires in {time}"
            }
        }
```

## 6.2 Form API Views

```python
# accounts/form_views.py
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from accounts.form_schemas import DynamicFormSchema, FormAction
from django.conf import settings
import re

@api_view(['GET'])
@permission_classes([AllowAny])
def get_form_schema_view(request):
    """Get dynamic form schema for specific action"""
    action = request.GET.get('action', 'login').lower()
    context = request.GET.get('context', {})
    
    # Get schema based on action
    if action == 'login':
        schema = DynamicFormSchema.get_login_schema()
    elif action == 'register':
        # Check if phone is required based on settings
        require_phone = settings.REQUIRE_PHONE_REGISTRATION
        schema = DynamicFormSchema.get_register_schema(require_phone)
    elif action == 'otp_verify':
        destination_type = request.GET.get('type', 'email')
        schema = DynamicFormSchema.get_otp_verification_schema(destination_type)
    elif action == 'reset_password':
        schema = {
            "form_id": "reset_password",
            "title": "Reset Password",
            "description": "Enter your email to receive reset instructions",
            "action": FormAction.RESET_PASSWORD,
            "submit_button": {
                "text": "Send Reset Link",
                "loading_text": "Sending..."
            },
            "fields": [
                {
                    "name": "email",
                    "type": "email",
                    "label": "Email Address",
                    "placeholder": "your@email.com",
                    "icon": "email",
                    "required": True,
                    "autofocus": True,
                    "validation": [
                        {"rule": "required", "message": "Email is required"},
                        {"rule": "email", "message": "Invalid email format"}
                    ]
                }
            ],
            "links": [
                {"text": "Back to login", "action": "login", "align": "center"}
            ]
        }
    else:
        return Response({
            'code': 'INVALID_ACTION',
            'message': f'Unknown form action: {action}'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Apply context-specific modifications
    if context:
        schema = apply_context_modifications(schema, context)
    
    # Add metadata
    schema['metadata'] = {
        'version': '1.0.0',
        'timestamp': timezone.now().isoformat(),
        'locale': request.GET.get('locale', 'en'),
        'theme': request.GET.get('theme', 'light')
    }
    
    return Response(schema, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def validate_field_view(request):
    """Validate single form field"""
    field_name = request.data.get('field')
    field_value = request.data.get('value')
    validation_rules = request.data.get('rules', [])
    form_data = request.data.get('form_data', {})
    
    errors = []
    
    for rule in validation_rules:
        rule_type = rule.get('rule')
        
        if rule_type == 'required' and not field_value:
            errors.append(rule.get('message', 'Field is required'))
            
        elif rule_type == 'min_length':
            min_len = rule.get('value', 0)
            if len(str(field_value)) < min_len:
                errors.append(rule.get('message', f'Minimum {min_len} characters'))
                
        elif rule_type == 'max_length':
            max_len = rule.get('value', 999)
            if len(str(field_value)) > max_len:
                errors.append(rule.get('message', f'Maximum {max_len} characters'))
                
        elif rule_type == 'pattern':
            pattern = rule.get('value', '')
            if not re.match(pattern, str(field_value)):
                errors.append(rule.get('message', 'Invalid format'))
                
        elif rule_type == 'email':
            from django.core.validators import validate_email
            from django.core.exceptions import ValidationError
            try:
                validate_email(field_value)
            except ValidationError:
                errors.append(rule.get('message', 'Invalid email address'))
                
        elif rule_type == 'phone':
            # Basic phone validation
            phone_pattern = r'^\+?[1-9]\d{1,14}$'
            if not re.match(phone_pattern, str(field_value)):
                errors.append(rule.get('message', 'Invalid phone number'))
                
        elif rule_type == 'match_field':
            match_field = rule.get('field')
            if field_value != form_data.get(match_field):
                errors.append(rule.get('message', 'Fields do not match'))
                
        elif rule_type == 'unique':
            model_name = rule.get('model')
            field = rule.get('field')
            
            # Check uniqueness in database
            if model_name == 'User':
                from accounts.models import User
                if User.objects.filter(**{field: field_value}).exists():
                    errors.append(rule.get('message', f'{field_name} already exists'))
                    
        elif rule_type == 'strong_password':
            # Check password strength
            if len(field_value) < 8:
                errors.append('Password must be at least 8 characters')
            if not re.search(r'[A-Z]', field_value):
                errors.append('Password must contain uppercase letter')
            if not re.search(r'[a-z]', field_value):
                errors.append('Password must contain lowercase letter')
            if not re.search(r'\d', field_value):
                errors.append('Password must contain number')
            if not re.search(r'[!@#$%^&*(),.?":{}|<>]', field_value):
                errors.append('Password must contain special character')
    
    if errors:
        return Response({
            'valid': False,
            'errors': errors
        }, status=status.HTTP_200_OK)
    
    return Response({
        'valid': True,
        'message': 'Field is valid'
    }, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def submit_dynamic_form_view(request):
    """Submit dynamic form and process based on action"""
    form_id = request.data.get('form_id')
    action = request.data.get('action')
    form_data = request.data.get('data', {})
    
    # Route to appropriate handler based on action
    if action == FormAction.LOGIN:
        return handle_login_submission(form_data, request)
    elif action == FormAction.REGISTER:
        return handle_registration_submission(form_data, request)
    elif action == FormAction.RESET_PASSWORD:
        return handle_password_reset_submission(form_data, request)
    elif action == FormAction.VERIFY_EMAIL:
        return handle_email_verification_submission(form_data, request)
    elif action == FormAction.VERIFY_PHONE:
        return handle_phone_verification_submission(form_data, request)
    else:
        return Response({
            'code': 'INVALID_ACTION',
            'message': f'Unknown form action: {action}'
        }, status=status.HTTP_400_BAD_REQUEST)

def handle_login_submission(data, request):
    """Handle login form submission"""
    from accounts.views import CustomTokenObtainPairView
    
    # Prepare login data
    login_data = {
        'username': data.get('username'),
        'password': data.get('password'),
    }
    
    # Add device info if available
    if 'install_id' in data:
        login_data['install_id'] = data['install_id']
    if 'platform' in data:
        login_data['platform'] = data['platform']
    
    # Use existing login view
    request._full_data = login_data
    view = CustomTokenObtainPairView.as_view()
    return view(request._request)

def handle_registration_submission(data, request):
    """Handle registration form submission"""
    from accounts.models import User
    from django.db import transaction
    
    try:
        with transaction.atomic():
            # Create user
            user = User.objects.create_user(
                username=data.get('username'),
                email=data.get('email'),
                password=data.get('password'),
                first_name=data.get('first_name', ''),
                last_name=data.get('last_name', ''),
            )
            
            # Add phone if provided
            if 'phone' in data:
                user.phone_e164 = data['phone']
                user.save()
            
            # Send verification email
            from otp_auth.models import OTPRequest
            from otp_auth.services import OTPService
            
            otp_request = OTPRequest.create_otp(
                otp_type='email',
                destination=user.email,
                purpose='verify',
                user=user,
                request=request
            )
            
            OTPService.send_email_otp(
                user.email,
                otp_request.otp_code,
                purpose='verify'
            )
            
            return Response({
                'message': 'Registration successful. Please verify your email.',
                'user_id': str(user.id),
                'verification_required': True,
                'verification_type': 'email'
            }, status=status.HTTP_201_CREATED)
            
    except Exception as e:
        return Response({
            'code': 'REGISTRATION_FAILED',
            'message': str(e)
        }, status=status.HTTP_400_BAD_REQUEST)

def apply_context_modifications(schema, context):
    """Apply context-specific modifications to form schema"""
    # Example: Hide social auth for enterprise context
    if context.get('enterprise'):
        schema['social_auth']['enabled'] = False
    
    # Example: Add custom fields for specific tenant
    if context.get('tenant_id'):
        # Add tenant-specific fields
        pass
    
    return schema
```

## 6.3 Form Configuration Settings

```python
# accounts/form_config.py
from django.conf import settings

class FormConfiguration:
    """Centralized form configuration"""
    
    # Field constraints
    USERNAME_MIN_LENGTH = 3
    USERNAME_MAX_LENGTH = 20
    PASSWORD_MIN_LENGTH = 8
    
    # Feature flags
    REQUIRE_EMAIL_VERIFICATION = True
    REQUIRE_PHONE_VERIFICATION = False
    ALLOW_USERNAME_LOGIN = True
    ALLOW_EMAIL_LOGIN = True
    ALLOW_PHONE_LOGIN = False
    
    # Social auth
    SOCIAL_AUTH_PROVIDERS = ['google', 'apple', 'facebook']
    
    # OTP settings
    OTP_LENGTH = 6
    OTP_EXPIRY_MINUTES = 10
    OTP_RESEND_COOLDOWN = 60
    
    # Password policy
    PASSWORD_REQUIRE_UPPERCASE = True
    PASSWORD_REQUIRE_LOWERCASE = True
    PASSWORD_REQUIRE_DIGIT = True
    PASSWORD_REQUIRE_SPECIAL = True
    
    @classmethod
    def get_config(cls):
        """Get form configuration as dict"""
        return {
            'username': {
                'min_length': cls.USERNAME_MIN_LENGTH,
                'max_length': cls.USERNAME_MAX_LENGTH,
                'pattern': '^[a-zA-Z0-9_]+$'
            },
            'password': {
                'min_length': cls.PASSWORD_MIN_LENGTH,
                'require_uppercase': cls.PASSWORD_REQUIRE_UPPERCASE,
                'require_lowercase': cls.PASSWORD_REQUIRE_LOWERCASE,
                'require_digit': cls.PASSWORD_REQUIRE_DIGIT,
                'require_special': cls.PASSWORD_REQUIRE_SPECIAL
            },
            'features': {
                'email_verification': cls.REQUIRE_EMAIL_VERIFICATION,
                'phone_verification': cls.REQUIRE_PHONE_VERIFICATION,
                'username_login': cls.ALLOW_USERNAME_LOGIN,
                'email_login': cls.ALLOW_EMAIL_LOGIN,
                'phone_login': cls.ALLOW_PHONE_LOGIN,
                'social_auth': cls.SOCIAL_AUTH_PROVIDERS
            },
            'otp': {
                'length': cls.OTP_LENGTH,
                'expiry': cls.OTP_EXPIRY_MINUTES,
                'resend_cooldown': cls.OTP_RESEND_COOLDOWN
            }
        }

@api_view(['GET'])
@permission_classes([AllowAny])
def get_form_config_view(request):
    """Get form configuration for client"""
    config = FormConfiguration.get_config()
    return Response(config, status=status.HTTP_200_OK)
```

## 6.4 Update URLs

```python
# accounts/urls.py (add to existing)
from accounts import form_views

urlpatterns = [
    # ... existing URLs
    path('forms/schema/', form_views.get_form_schema_view, name='form_schema'),
    path('forms/validate/', form_views.validate_field_view, name='validate_field'),
    path('forms/submit/', form_views.submit_dynamic_form_view, name='submit_form'),
    path('forms/config/', form_views.get_form_config_view, name='form_config'),
]
```

## Testing

### Get login form schema
```bash
curl -X GET "http://localhost:8000/api/auth/forms/schema/?action=login"
```

### Get registration form schema
```bash
curl -X GET "http://localhost:8000/api/auth/forms/schema/?action=register"
```

### Validate field
```bash
curl -X POST http://localhost:8000/api/auth/forms/validate/ \
  -H "Content-Type: application/json" \
  -d '{
    "field": "email",
    "value": "test@example.com",
    "rules": [
      {"rule": "required"},
      {"rule": "email"},
      {"rule": "unique", "model": "User", "field": "email"}
    ]
  }'
```

### Submit form
```bash
curl -X POST http://localhost:8000/api/auth/forms/submit/ \
  -H "Content-Type: application/json" \
  -d '{
    "form_id": "login_form",
    "action": "login",
    "data": {
      "username": "testuser",
      "password": "TestPass123!"
    }
  }'
```

## Flutter Integration Notes

1. **Form Rendering**: Use schema to dynamically build forms
2. **Real-time Validation**: Call validate endpoint on field blur
3. **Error Display**: Show inline errors from validation
4. **Progress Indicators**: Use loading states from schema
5. **Conditional Fields**: Show/hide fields based on conditions
6. **Theme Support**: Apply theme from metadata

## Security Considerations

1. **Rate Limiting**: Apply on validation and submission endpoints
2. **CSRF Protection**: Enable for form submissions
3. **Input Sanitization**: Clean all user inputs
4. **Unique Checks**: Cache results to prevent enumeration
5. **Password Policies**: Enforce strong passwords server-side

## Next Steps

✅ Dynamic form schemas
✅ Field validation API
✅ Form submission handling
✅ Configuration management
✅ Integration with auth flows

Continue to [Part 7: Version Gate API](./part7-version-gate.md)
