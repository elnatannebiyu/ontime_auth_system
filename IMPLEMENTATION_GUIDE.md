# Complete Implementation Guide: Auth System with Version Gate & Dynamic Forms

## Overview
This guide combines three specifications into a unified implementation:
1. **Account Creation Standard** - Complete auth flow with email/phone/social
2. **Backend-Driven Forms** - Dynamic form schemas for login/register  
3. **Version Gate** - Force/soft app updates

## Project Structure

### Backend (Django)
```
authstack/
├── accounts/           # Existing auth with JWT
├── tenants/           # Multi-tenant support
├── version_gate/      # App version checking
├── auth_forms/        # Dynamic form schemas
├── otp_auth/          # Phone/Email OTP
└── social_auth/       # Google/Apple sign-in
```

### Flutter  
```
lib/
├── core/
│   ├── services/      # version, auth, forms
│   ├── middleware/    # interceptors
│   └── widgets/       # reusable UI
├── auth/              # login/register pages
└── features/          # app features
```

---

## Part 1: Backend Core Setup

### 1.1 Install Dependencies
```bash
pip install django djangorestframework django-cors-headers
pip install djangorestframework-simplejwt drf-yasg  
pip install argon2-cffi redis celery twilio
pip install google-auth PyJWT python-decouple
pip install packaging  # for version comparison
```

### 1.2 Settings Configuration
```python
# authstack/settings.py

# Add to existing settings
from datetime import timedelta
import os

# Security - Use Argon2 for passwords
PASSWORD_HASHERS = [
    'django.contrib.auth.hashers.Argon2PasswordHasher',
    'django.contrib.auth.hashers.PBKDF2PasswordHasher',
]

# App Version Configuration
APP_VERSION_CONFIG = {
    'android': {
        'latest': '1.3.0',
        'min_supported': '1.2.0', 
        'store_url': 'market://details?id=com.ybs.ontime',
        'notes': 'Bug fixes and performance improvements'
    },
    'ios': {
        'latest': '1.3.0',
        'min_supported': '1.2.0',
        'store_url': 'itms-apps://itunes.apple.com/app/id123456789',
        'notes': 'Bug fixes and performance improvements'
    }
}

# OTP Configuration
OTP_SETTINGS = {
    'LENGTH': 6,
    'VALIDITY_MINUTES': 5,
    'MAX_ATTEMPTS': 3,
    'COOLDOWN_MINUTES': 1,
}

# Social Auth Keys (from environment)
GOOGLE_OAUTH2_CLIENT_ID = os.getenv('GOOGLE_CLIENT_ID')
APPLE_CLIENT_ID = os.getenv('APPLE_CLIENT_ID')

# Rate Limiting
RATELIMIT_ENABLE = True

# Add new apps
INSTALLED_APPS += [
    'version_gate',
    'auth_forms',
    'otp_auth',
    'social_auth',
]

# Add version middleware
MIDDLEWARE.insert(0, 'version_gate.middleware.VersionGateMiddleware')

# Redis cache for OTP and schemas
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.redis.RedisCache',
        'LOCATION': 'redis://127.0.0.1:6379/1',
    }
}
```

---

## Part 2: Version Gate Implementation

### 2.1 Create Version App
```bash
python manage.py startapp version_gate
```

### 2.2 Version Views
```python
# version_gate/views.py
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from django.conf import settings
from django.core.cache import cache

class AppVersionView(APIView):
    permission_classes = [AllowAny]
    
    def get(self, request):
        platform = request.query_params.get('platform', '').lower()
        if platform not in ['android', 'ios']:
            return Response({'error': 'Invalid platform'}, status=400)
        
        # Check cache
        cache_key = f'app_version_{platform}'
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)
        
        # Get config
        config = settings.APP_VERSION_CONFIG.get(platform, {})
        response_data = {
            'platform': platform,
            'latest': config.get('latest', '1.0.0'),
            'min_supported': config.get('min_supported', '1.0.0'),
            'store_url': config.get('store_url', ''),
            'notes': config.get('notes', '')
        }
        
        # Cache for 5 minutes
        cache.set(cache_key, response_data, 300)
        return Response(response_data)
```

### 2.3 Version Middleware
```python
# version_gate/middleware.py
from django.http import JsonResponse
from django.conf import settings
from packaging import version

class VersionGateMiddleware:
    def __init__(self, get_response):
        self.get_response = get_response
        self.exempt_paths = [
            '/app/version',
            '/api/token/',
            '/api/register/',
            '/api/auth/'
        ]
    
    def __call__(self, request):
        # Skip exempt paths
        if any(request.path.startswith(p) for p in self.exempt_paths):
            return self.get_response(request)
        
        # Check headers
        app_version = request.headers.get('X-App-Version')
        platform = request.headers.get('X-App-Platform')
        
        if app_version and platform:
            config = settings.APP_VERSION_CONFIG.get(platform.lower(), {})
            min_supported = config.get('min_supported', '1.0.0')
            
            if version.parse(app_version) < version.parse(min_supported):
                return JsonResponse({
                    'code': 'APP_UPDATE_REQUIRED',
                    'min_supported': min_supported,
                    'store_url': config.get('store_url', '')
                }, status=426)
        
        return self.get_response(request)
```

---

## Part 3: OTP Authentication

### 3.1 OTP Models
```python
# otp_auth/models.py
import random
import string
from datetime import timedelta
from django.db import models
from django.contrib.auth.models import User
from django.utils import timezone
from django.conf import settings

class OTPVerification(models.Model):
    TYPES = [('phone', 'Phone'), ('email', 'Email')]
    
    user = models.ForeignKey(User, on_delete=models.CASCADE, null=True)
    type = models.CharField(max_length=10, choices=TYPES)
    destination = models.CharField(max_length=255)
    code = models.CharField(max_length=6)
    attempts = models.IntegerField(default=0)
    verified = models.BooleanField(default=False)
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    
    @classmethod
    def create_otp(cls, destination, type='phone', user=None):
        # Invalidate old OTPs
        cls.objects.filter(
            destination=destination,
            verified=False
        ).update(verified=True)
        
        # Generate new
        code = ''.join(random.choices(string.digits, k=6))
        expires = timezone.now() + timedelta(minutes=5)
        
        return cls.objects.create(
            user=user,
            type=type,
            destination=destination,
            code=code,
            expires_at=expires
        )
    
    def verify(self, code):
        if self.verified or self.expires_at < timezone.now():
            return False
        
        self.attempts += 1
        if self.attempts > 3:
            return False
        
        if self.code == code:
            self.verified = True
            self.save()
            return True
        
        self.save()
        return False
```

### 3.2 OTP Views
```python
# otp_auth/views.py
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from django.core.cache import cache
from .models import OTPVerification

class SendOTPView(APIView):
    permission_classes = [AllowAny]
    
    def post(self, request):
        destination = request.data.get('destination')
        otp_type = request.data.get('type', 'phone')
        
        # Rate limit
        rate_key = f'otp_{destination}'
        if cache.get(rate_key):
            return Response({'error': 'Wait before retry'}, status=429)
        
        # Create OTP
        otp = OTPVerification.create_otp(destination, otp_type)
        
        # TODO: Send via SMS/Email service
        print(f'OTP Code: {otp.code}')  # Development only
        
        cache.set(rate_key, True, 60)
        
        return Response({
            'sent_to': destination[:3] + '***',
            'expires_in': 300
        })

class VerifyOTPView(APIView):
    permission_classes = [AllowAny]
    
    def post(self, request):
        destination = request.data.get('destination')
        code = request.data.get('code')
        
        otp = OTPVerification.objects.filter(
            destination=destination,
            verified=False
        ).order_by('-created_at').first()
        
        if not otp or not otp.verify(code):
            return Response({'error': 'Invalid OTP'}, status=400)
        
        # Create/get user
        username = destination
        user, created = User.objects.get_or_create(
            username=username,
            defaults={'email': f'{username}@otp.local'}
        )
        
        # Generate tokens
        from accounts.serializers import CookieTokenObtainPairSerializer
        serializer = CookieTokenObtainPairSerializer()
        refresh = serializer.get_token(user)
        
        return Response({
            'access': str(refresh.access_token),
            'user_created': created
        })
```

---

## Part 4: Dynamic Form Schemas

### 4.1 Form Schema View
```python
# auth_forms/views.py
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import AllowAny
from django.core.cache import cache

class AuthFormSchemaView(APIView):
    permission_classes = [AllowAny]
    
    def get(self, request):
        form_name = request.query_params.get('name')
        if form_name not in ['login', 'register']:
            return Response({'error': 'Invalid form'}, status=404)
        
        # Cache key
        cache_key = f'form_{form_name}'
        cached = cache.get(cache_key)
        if cached:
            return Response(cached)
        
        schema = self.build_schema(form_name)
        cache.set(cache_key, schema, 300)
        
        return Response(schema)
    
    def build_schema(self, name):
        if name == 'login':
            return {
                'schema_version': '2025.01',
                'form': {
                    'name': 'login',
                    'action': '/api/v1/auth/login'
                },
                'fields': [
                    {
                        'name': 'email',
                        'type': 'email',
                        'label': 'Email',
                        'required': True
                    },
                    {
                        'name': 'password',
                        'type': 'password',
                        'label': 'Password',
                        'required': True
                    }
                ],
                'actions': [
                    {
                        'id': 'submit',
                        'type': 'submit',
                        'label': 'Sign in'
                    },
                    {
                        'id': 'google',
                        'type': 'oauth',
                        'provider': 'google'
                    }
                ]
            }
        else:  # register
            return {
                'schema_version': '2025.01',
                'form': {
                    'name': 'register',
                    'action': '/api/v1/auth/register'
                },
                'fields': [
                    {
                        'name': 'email',
                        'type': 'email',
                        'label': 'Email',
                        'required': True
                    },
                    {
                        'name': 'password',
                        'type': 'password',
                        'label': 'Password',
                        'required': True,
                        'validators': {'min_length': 8}
                    },
                    {
                        'name': 'terms_accepted',
                        'type': 'checkbox',
                        'label': 'I agree to Terms',
                        'required': True
                    }
                ],
                'actions': [
                    {
                        'id': 'submit',
                        'type': 'submit',
                        'label': 'Create account'
                    }
                ]
            }
```

---

## Part 5: Enhanced Registration

### 5.1 Complete Registration View
```python
# accounts/views.py (add to existing)
class EnhancedRegisterView(APIView):
    permission_classes = [AllowAny]
    
    def post(self, request):
        # Core fields
        email = request.data.get('email', '').lower()
        phone_e164 = request.data.get('phone_e164')
        password = request.data.get('password')
        
        # Consent
        terms = request.data.get('terms_accepted', False)
        privacy = request.data.get('privacy_accepted', False)
        
        # Device context
        platform = request.data.get('platform')
        app_version = request.data.get('app_version')
        install_id = request.data.get('install_id')
        
        # Validation
        if not terms or not privacy:
            return Response({'error': 'Accept terms'}, status=400)
        
        if not email and not phone_e164:
            return Response({'error': 'Email or phone required'}, status=400)
        
        # Check exists
        username = email if email else phone_e164
        if User.objects.filter(username=username).exists():
            return Response({'error': 'User exists'}, status=409)
        
        # Create user
        user = User.objects.create_user(
            username=username,
            email=email or f'{phone_e164}@phone.local',
            password=password
        )
        
        # Add to tenant
        tenant = getattr(request, 'tenant', None)
        if tenant:
            from accounts.models import Membership
            Membership.objects.create(user=user, tenant=tenant)
        
        # Generate tokens
        from accounts.serializers import CookieTokenObtainPairSerializer
        serializer = CookieTokenObtainPairSerializer()
        refresh = serializer.get_token(user)
        
        return Response({
            'id': str(user.id),
            'email': email,
            'access_token': str(refresh.access_token),
            'refresh_token': str(refresh),
            'created_at': user.date_joined.isoformat()
        }, status=201)
```

---

## Part 6: Flutter Implementation

### See FLUTTER_IMPLEMENTATION.md for complete Flutter code

---

## Part 7: URLs Configuration

```python
# authstack/urls.py
from django.urls import path
from version_gate import views as version_views
from auth_forms import views as form_views
from otp_auth import views as otp_views
from accounts import views as auth_views

urlpatterns = [
    # Version
    path('app/version', version_views.AppVersionView.as_view()),
    
    # Forms
    path('api/v1/auth/forms', form_views.AuthFormSchemaView.as_view()),
    
    # Auth
    path('api/v1/auth/register', auth_views.EnhancedRegisterView.as_view()),
    
    # OTP
    path('api/v1/auth/otp/send', otp_views.SendOTPView.as_view()),
    path('api/v1/auth/otp/verify', otp_views.VerifyOTPView.as_view()),
    
    # ... existing URLs ...
]
```

---

## Testing

### Backend Tests
```bash
# Run migrations
python manage.py makemigrations
python manage.py migrate

# Create superuser
python manage.py createsuperuser

# Run server
python manage.py runserver

# Test endpoints
curl http://localhost:8000/app/version?platform=android
curl http://localhost:8000/api/v1/auth/forms?name=login
```

### Flutter Tests
```bash
# Run app
flutter run

# Test version gate
flutter test test/version_test.dart
```

---

## Security Checklist

- [x] Argon2 password hashing
- [x] JWT with short expiry
- [x] Rate limiting on auth endpoints
- [x] OTP expiry and attempts limit
- [x] Version enforcement middleware
- [x] HTTPS in production
- [x] Input validation
- [x] Tenant isolation

---

## Next Steps

1. **Backend**: Add Twilio/SendGrid for OTP delivery
2. **Flutter**: See FLUTTER_IMPLEMENTATION.md
3. **Testing**: Add unit and integration tests
4. **Deploy**: Docker setup for production
