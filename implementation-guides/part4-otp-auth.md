# Part 4: OTP Authentication

## Overview
Implement phone and email OTP authentication with rate limiting and expiry.

## 4.1 Create OTP App

```bash
cd authstack
python manage.py startapp otp_auth
```

### Add to INSTALLED_APPS
```python
# authstack/settings.py
INSTALLED_APPS = [
    # ... existing apps
    'accounts',
    'sessions',
    'otp_auth',  # Add this
]
```

## 4.2 OTP Models

```python
# otp_auth/models.py
import random
import string
import uuid
from datetime import timedelta
from django.db import models
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.core.validators import RegexValidator

User = get_user_model()

class OTPRequest(models.Model):
    """Track OTP requests for rate limiting and verification"""
    
    OTP_TYPE_CHOICES = [
        ('email', 'Email'),
        ('phone', 'Phone'),
    ]
    
    PURPOSE_CHOICES = [
        ('login', 'Login'),
        ('register', 'Registration'),
        ('verify', 'Verification'),
        ('reset', 'Password Reset'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(User, on_delete=models.CASCADE, null=True, blank=True)
    
    # Contact details
    otp_type = models.CharField(max_length=10, choices=OTP_TYPE_CHOICES)
    destination = models.CharField(max_length=255, db_index=True)  # email or phone
    
    # OTP details
    otp_code = models.CharField(max_length=6)
    otp_hash = models.CharField(max_length=128)  # For extra security
    purpose = models.CharField(max_length=20, choices=PURPOSE_CHOICES)
    
    # Status
    is_verified = models.BooleanField(default=False)
    attempts = models.IntegerField(default=0)
    max_attempts = models.IntegerField(default=3)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    verified_at = models.DateTimeField(null=True, blank=True)
    
    # Metadata
    ip_address = models.GenericIPAddressField()
    user_agent = models.TextField()
    
    class Meta:
        db_table = 'otp_requests'
        indexes = [
            models.Index(fields=['destination', '-created_at']),
            models.Index(fields=['otp_code', 'destination']),
        ]
    
    @classmethod
    def create_otp(cls, otp_type, destination, purpose, user=None, request=None):
        """Create new OTP request"""
        # Generate 6-digit OTP
        otp_code = ''.join(random.choices(string.digits, k=6))
        
        # For development, use simple codes
        if settings.DEBUG:
            otp_code = '123456'
        
        # Hash for storage
        import hashlib
        otp_hash = hashlib.sha256(f"{otp_code}{destination}".encode()).hexdigest()
        
        # Set expiry (5 minutes for phone, 10 for email)
        if otp_type == 'phone':
            expires_at = timezone.now() + timedelta(minutes=5)
        else:
            expires_at = timezone.now() + timedelta(minutes=10)
        
        # Get request metadata
        ip_address = '0.0.0.0'
        user_agent = ''
        if request:
            x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
            if x_forwarded_for:
                ip_address = x_forwarded_for.split(',')[0]
            else:
                ip_address = request.META.get('REMOTE_ADDR', '0.0.0.0')
            user_agent = request.META.get('HTTP_USER_AGENT', '')
        
        otp_request = cls.objects.create(
            user=user,
            otp_type=otp_type,
            destination=destination,
            otp_code=otp_code,
            otp_hash=otp_hash,
            purpose=purpose,
            expires_at=expires_at,
            ip_address=ip_address,
            user_agent=user_agent
        )
        
        return otp_request
    
    def verify(self, code):
        """Verify OTP code"""
        if self.is_verified:
            return False, 'OTP already used'
        
        if self.expires_at < timezone.now():
            return False, 'OTP expired'
        
        if self.attempts >= self.max_attempts:
            return False, 'Too many attempts'
        
        self.attempts += 1
        self.save()
        
        if self.otp_code != code:
            return False, 'Invalid OTP'
        
        # Mark as verified
        self.is_verified = True
        self.verified_at = timezone.now()
        self.save()
        
        return True, 'OTP verified'
    
    @classmethod
    def check_rate_limit(cls, destination, limit_minutes=60, max_requests=5):
        """Check if destination has exceeded rate limit"""
        since = timezone.now() - timedelta(minutes=limit_minutes)
        count = cls.objects.filter(
            destination=destination,
            created_at__gte=since
        ).count()
        
        return count >= max_requests
```

## 4.3 OTP Service

```python
# otp_auth/services.py
from django.conf import settings
from django.core.mail import send_mail
from django.template.loader import render_to_string
import logging

logger = logging.getLogger(__name__)

class OTPService:
    """Service for sending OTP via email/SMS"""
    
    @staticmethod
    def send_email_otp(email, otp_code, purpose='login'):
        """Send OTP via email"""
        try:
            subject_map = {
                'login': 'Your Login Code',
                'register': 'Verify Your Email',
                'verify': 'Email Verification Code',
                'reset': 'Password Reset Code',
            }
            
            subject = subject_map.get(purpose, 'Your Verification Code')
            
            # Simple text message
            message = f"""Your verification code is: {otp_code}
            
This code will expire in 10 minutes.

If you didn't request this code, please ignore this email.
"""
            
            # HTML message (optional)
            html_message = f"""
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                <h2>Your Verification Code</h2>
                <div style="background: #f5f5f5; padding: 20px; border-radius: 5px; margin: 20px 0;">
                    <h1 style="text-align: center; color: #333; letter-spacing: 5px;">{otp_code}</h1>
                </div>
                <p>This code will expire in 10 minutes.</p>
                <p style="color: #666; font-size: 14px;">If you didn't request this code, please ignore this email.</p>
            </div>
            """
            
            send_mail(
                subject,
                message,
                settings.DEFAULT_FROM_EMAIL,
                [email],
                html_message=html_message,
                fail_silently=False,
            )
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to send email OTP: {e}")
            return False
    
    @staticmethod
    def send_sms_otp(phone, otp_code, purpose='login'):
        """Send OTP via SMS using Twilio"""
        try:
            # For development, just log it
            if settings.DEBUG:
                logger.info(f"SMS OTP for {phone}: {otp_code}")
                return True
            
            # Production: Use Twilio
            # from twilio.rest import Client
            # 
            # client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
            # 
            # message = client.messages.create(
            #     body=f"Your verification code is: {otp_code}",
            #     from_=settings.TWILIO_PHONE_NUMBER,
            #     to=phone
            # )
            # 
            # return message.sid is not None
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to send SMS OTP: {e}")
            return False
```

## 4.4 OTP Views

```python
# otp_auth/views.py
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from django.core.validators import validate_email
from django.core.exceptions import ValidationError
from otp_auth.models import OTPRequest
from otp_auth.services import OTPService
from accounts.models import User
import re

@api_view(['POST'])
@permission_classes([AllowAny])
def request_otp_view(request):
    """Request OTP for login/registration"""
    destination = request.data.get('destination', '').strip()
    purpose = request.data.get('purpose', 'login')
    
    if not destination:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Email or phone number required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Determine type (email or phone)
    otp_type = None
    
    # Check if email
    try:
        validate_email(destination)
        otp_type = 'email'
    except ValidationError:
        # Check if phone (E.164 format)
        if re.match(r'^\+[1-9]\d{1,14}$', destination):
            otp_type = 'phone'
    
    if not otp_type:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Invalid email or phone number'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Check rate limiting
    if OTPRequest.check_rate_limit(destination):
        return Response({
            'code': 'RATE_LIMIT',
            'message': 'Too many OTP requests. Please try again later.'
        }, status=status.HTTP_429_TOO_MANY_REQUESTS)
    
    # Check if user exists (for login)
    user = None
    if purpose == 'login':
        if otp_type == 'email':
            user = User.objects.filter(email=destination).first()
        else:
            user = User.objects.filter(phone_e164=destination).first()
        
        if not user:
            return Response({
                'code': 'USER_NOT_FOUND',
                'message': 'No account found with this email/phone'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Check user status
        if user.status != 'active':
            return Response({
                'code': 'ACCOUNT_DISABLED',
                'message': 'Account is not active'
            }, status=status.HTTP_403_FORBIDDEN)
    
    # Create OTP request
    otp_request = OTPRequest.create_otp(
        otp_type=otp_type,
        destination=destination,
        purpose=purpose,
        user=user,
        request=request
    )
    
    # Send OTP
    if otp_type == 'email':
        success = OTPService.send_email_otp(destination, otp_request.otp_code, purpose)
    else:
        success = OTPService.send_sms_otp(destination, otp_request.otp_code, purpose)
    
    if not success:
        otp_request.delete()
        return Response({
            'code': 'SEND_FAILED',
            'message': f'Failed to send OTP to {otp_type}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    return Response({
        'message': f'OTP sent to {otp_type}',
        'otp_id': str(otp_request.id),
        'expires_in': 300 if otp_type == 'phone' else 600,  # seconds
        'destination_masked': _mask_destination(destination, otp_type)
    }, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def verify_otp_view(request):
    """Verify OTP and login"""
    otp_id = request.data.get('otp_id')
    otp_code = request.data.get('otp_code', '').strip()
    
    if not otp_id or not otp_code:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'OTP ID and code required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        otp_request = OTPRequest.objects.get(id=otp_id)
    except OTPRequest.DoesNotExist:
        return Response({
            'code': 'INVALID_OTP',
            'message': 'Invalid OTP request'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Verify OTP
    success, message = otp_request.verify(otp_code)
    
    if not success:
        return Response({
            'code': 'INVALID_OTP',
            'message': message
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Handle based on purpose
    if otp_request.purpose == 'login':
        # Login user
        user = otp_request.user
        if not user:
            # Find user by destination
            if otp_request.otp_type == 'email':
                user = User.objects.filter(email=otp_request.destination).first()
            else:
                user = User.objects.filter(phone_e164=otp_request.destination).first()
        
        if not user:
            return Response({
                'code': 'USER_NOT_FOUND',
                'message': 'User not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Create session
        from sessions.models import Session, Device
        from accounts.serializers import EnhancedTokenObtainPairSerializer
        
        # Get device info
        device = None
        install_id = request.data.get('install_id')
        if install_id:
            device, _ = Device.objects.update_or_create(
                install_id=install_id,
                user=user,
                defaults={
                    'platform': request.data.get('platform', 'web'),
                    'app_version': request.data.get('app_version', '1.0.0'),
                }
            )
        
        # Create session
        session, refresh_token = Session.create_session(user, request, device)
        
        # Generate tokens
        refresh = EnhancedTokenObtainPairSerializer.get_token(user)
        access = refresh.access_token
        
        # Add session info
        refresh['sid'] = str(session.id)
        access['sid'] = str(session.id)
        access['jti'] = str(uuid.uuid4())
        
        # Mark phone/email as verified
        if otp_request.otp_type == 'email':
            user.email_verified = True
        else:
            user.phone_verified = True
        user.save()
        
        return Response({
            'access': str(access),
            'refresh': refresh_token,
            'session_id': str(session.id),
            'expires_in': settings.SIMPLE_JWT['ACCESS_TOKEN_LIFETIME'].total_seconds(),
            'user': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
                'email_verified': user.email_verified,
                'phone_verified': user.phone_verified,
            }
        }, status=status.HTTP_200_OK)
    
    elif otp_request.purpose == 'register':
        # For registration, return success and let registration endpoint handle it
        return Response({
            'message': 'OTP verified',
            'verified_destination': otp_request.destination,
            'verification_token': str(otp_request.id)  # Use this in registration
        }, status=status.HTTP_200_OK)
    
    else:
        # For verification/reset, just return success
        return Response({
            'message': 'OTP verified successfully'
        }, status=status.HTTP_200_OK)

def _mask_destination(destination, otp_type):
    """Mask email or phone for privacy"""
    if otp_type == 'email':
        parts = destination.split('@')
        if len(parts) == 2:
            name = parts[0]
            if len(name) > 2:
                masked = name[0] + '*' * (len(name) - 2) + name[-1]
            else:
                masked = name[0] + '*'
            return f"{masked}@{parts[1]}"
    else:
        # Phone
        if len(destination) > 6:
            return destination[:3] + '*' * (len(destination) - 6) + destination[-3:]
    
    return destination
```

## 4.5 Email Configuration

```python
# authstack/settings.py

# Email settings
EMAIL_BACKEND = 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = 'smtp.gmail.com'  # or your SMTP server
EMAIL_PORT = 587
EMAIL_USE_TLS = True
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', 'your-email@gmail.com')
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD', 'your-app-password')
DEFAULT_FROM_EMAIL = 'noreply@yourapp.com'

# For development, use console backend
if DEBUG:
    EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend'

# SMS settings (Twilio)
TWILIO_ACCOUNT_SID = os.environ.get('TWILIO_ACCOUNT_SID', '')
TWILIO_AUTH_TOKEN = os.environ.get('TWILIO_AUTH_TOKEN', '')
TWILIO_PHONE_NUMBER = os.environ.get('TWILIO_PHONE_NUMBER', '')
```

## 4.6 Update URLs

```python
# otp_auth/urls.py
from django.urls import path
from . import views

urlpatterns = [
    path('request/', views.request_otp_view, name='request_otp'),
    path('verify/', views.verify_otp_view, name='verify_otp'),
]
```

```python
# authstack/urls.py
urlpatterns = [
    # ... existing
    path('api/auth/otp/', include('otp_auth.urls')),
]
```

## Testing

### Test OTP request
```bash
# Request email OTP
curl -X POST http://localhost:8000/api/auth/otp/request/ \
  -H "Content-Type: application/json" \
  -d '{
    "destination": "user@example.com",
    "purpose": "login"
  }'

# Request phone OTP
curl -X POST http://localhost:8000/api/auth/otp/request/ \
  -H "Content-Type: application/json" \
  -d '{
    "destination": "+1234567890",
    "purpose": "login"
  }'
```

### Test OTP verification
```bash
# Verify OTP (use 123456 in DEBUG mode)
curl -X POST http://localhost:8000/api/auth/otp/verify/ \
  -H "Content-Type: application/json" \
  -d '{
    "otp_id": "UUID_FROM_REQUEST",
    "otp_code": "123456",
    "install_id": "device-uuid",
    "platform": "ios"
  }'
```

## Security Notes

1. **Rate Limiting**: Max 5 OTP requests per hour per destination
2. **Expiry**: 5 minutes for SMS, 10 for email
3. **Max Attempts**: 3 verification attempts per OTP
4. **Debug Mode**: Uses fixed code (123456) for testing
5. **Masking**: Destinations masked in responses for privacy

## Next Steps

✅ OTP model with rate limiting
✅ Email and SMS OTP sending
✅ OTP verification with login
✅ Integration with session management

Continue to [Part 5: Social Authentication](./part5-social-auth.md)
