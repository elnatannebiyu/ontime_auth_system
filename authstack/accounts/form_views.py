from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from accounts.form_schemas import DynamicFormSchema, FormAction
from django.conf import settings
from django.utils import timezone
import re


@api_view(['GET'])
@permission_classes([AllowAny])
def get_form_schema_view(request):
    """Get dynamic form schema for specific action"""
    action = request.GET.get('action', 'login').lower()
    context_str = request.GET.get('context', None)
    
    # Get form schema based on action
    if action == 'login':
        schema = DynamicFormSchema.get_login_schema()
    elif action == 'register':
        schema = DynamicFormSchema.get_register_schema()
    elif action == 'verify_email':
        schema = DynamicFormSchema.get_email_verification_schema()
    elif action == 'verify_phone':
        schema = DynamicFormSchema.get_phone_verification_schema()
    elif action == 'verify_otp':
        # OTP verification form (generic)
        schema = {
            "action": "verify_otp",
            "form_id": "otp_verification_form",
            "title": "Verify OTP",
            "description": "Enter the verification code",
            "fields": [
                {
                    "name": "identifier",
                    "type": "text",
                    "label": "Email or Phone",
                    "placeholder": "Enter email or phone",
                    "required": True,
                    "validation": [
                        {"rule": "required", "message": "Identifier is required"}
                    ]
                },
                {
                    "name": "otp_code",
                    "type": "text",
                    "label": "Verification Code",
                    "placeholder": "Enter 6-digit code",
                    "required": True,
                    "maxLength": 6,
                    "validation": [
                        {"rule": "required", "message": "Code is required"},
                        {"rule": "pattern", "value": "^[0-9]{6}$", "message": "Must be 6 digits"}
                    ]
                }
            ],
            "submit_button": {
                "text": "Verify",
                "loading_text": "Verifying..."
            },
            "social_auth": {"enabled": False}
        }
    elif action == 'reset_password':
        schema = {
            "action": "reset_password",
            "form_id": "reset_password",
            "title": "Reset Password",
            "description": "Enter your email to receive reset instructions",
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
            ],
            "social_auth": {"enabled": False}
        }
    else:
        return Response({
            'error': f'Unknown form action: {action}'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Apply context modifications if provided
    if context_str:
        try:
            context = json.loads(context_str)
            schema = apply_context_modifications(schema, context)
        except json.JSONDecodeError:
            pass
    
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
                from django.contrib.auth import get_user_model
                User = get_user_model()
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
            'error': f'Unknown form action: {action}'
        }, status=status.HTTP_400_BAD_REQUEST)


def handle_login_submission(data, request):
    """Handle login form submission"""
    from accounts.views import TokenObtainPairWithCookieView
    from rest_framework.test import APIRequestFactory
    
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
    
    # Create a new request with the login data
    factory = APIRequestFactory()
    new_request = factory.post('/api/token/', login_data, format='json')
    
    # Copy over important attributes from original request
    new_request.META = request.META.copy()
    new_request.tenant = getattr(request, 'tenant', None)
    
    # Use existing login view
    view = TokenObtainPairWithCookieView.as_view()
    return view(new_request)


def handle_registration_submission(data, request):
    """Handle registration form submission"""
    from django.contrib.auth import get_user_model
    from django.db import transaction
    
    User = get_user_model()
    
    # Check password confirmation
    if data.get('password') != data.get('confirm_password'):
        return Response({
            'error': 'Passwords do not match'
        }, status=status.HTTP_400_BAD_REQUEST)
    
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
            'error': str(e)
        }, status=status.HTTP_400_BAD_REQUEST)


def handle_password_reset_submission(data, request):
    """Handle password reset form submission"""
    email = data.get('email')
    
    if not email:
        return Response({
            'error': 'Email is required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    from accounts.models import User
    from otp_auth.models import OTPRequest
    from otp_auth.services import OTPService
    
    try:
        user = User.objects.get(email=email)
        
        # Create OTP for password reset
        otp_request = OTPRequest.create_otp(
            otp_type='email',
            destination=email,
            purpose='reset',
            user=user,
            request=request
        )
        
        # Send OTP email
        OTPService.send_email_otp(
            email,
            otp_request.otp_code,
            purpose='reset'
        )
        
        return Response({
            'message': 'Password reset instructions sent to your email',
            'otp_id': str(otp_request.id)
        }, status=status.HTTP_200_OK)
        
    except User.DoesNotExist:
        # Don't reveal if user exists
        return Response({
            'message': 'If an account exists with this email, you will receive reset instructions'
        }, status=status.HTTP_200_OK)


def handle_email_verification_submission(data, request):
    """Handle email verification form submission"""
    from otp_auth.views import verify_otp_view
    from rest_framework.test import APIRequestFactory
    
    # Prepare verification data
    verify_data = {
        'otp_type': 'email',
        'destination': data.get('email'),
        'otp_code': data.get('otp_code'),
        'purpose': 'verify'
    }
    
    # Create a new request
    factory = APIRequestFactory()
    new_request = factory.post('/api/auth/otp/verify/', verify_data, format='json')
    new_request.META = request.META.copy()
    new_request.tenant = getattr(request, 'tenant', None)
    
    # Use existing OTP verification view
    return verify_otp_view(new_request)


def handle_phone_verification_submission(data, request):
    """Handle phone verification form submission"""
    from otp_auth.views import verify_otp_view
    from rest_framework.test import APIRequestFactory
    
    # Prepare verification data
    verify_data = {
        'otp_type': 'phone',
        'destination': data.get('phone'),
        'otp_code': data.get('otp_code'),
        'purpose': 'verify'
    }
    
    # Create a new request
    factory = APIRequestFactory()
    new_request = factory.post('/api/auth/otp/verify/', verify_data, format='json')
    new_request.META = request.META.copy()
    new_request.tenant = getattr(request, 'tenant', None)
    
    # Use existing OTP verification view
    return verify_otp_view(new_request)


def apply_context_modifications(schema, context):
    """Apply context-based modifications to form schema"""
    if not isinstance(context, dict):
        return schema
        
    if context.get('enterprise'):
        # Hide social auth for enterprise context
        schema['social_auth']['enabled'] = False
    
    if context.get('disable_social'):
        # Disable social auth
        schema['social_auth']['enabled'] = False
    
    # Example: Add custom fields for specific tenant
    if context.get('tenant_id'):
        # Add tenant-specific fields
        pass
    
    return schema
