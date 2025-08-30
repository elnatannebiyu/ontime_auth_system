# Part 2: JWT with Token Versioning

## Overview
Enhance JWT tokens with session tracking and token versioning for instant revocation.

## 2.1 Update JWT Settings

```python
# authstack/settings.py
from datetime import timedelta

SIMPLE_JWT = {
    'ACCESS_TOKEN_LIFETIME': timedelta(minutes=5),  # Short-lived
    'REFRESH_TOKEN_LIFETIME': timedelta(days=30),
    'ROTATE_REFRESH_TOKENS': True,
    'BLACKLIST_AFTER_ROTATION': False,  # We handle this manually
    
    'ALGORITHM': 'HS256',
    'SIGNING_KEY': SECRET_KEY,
    'VERIFYING_KEY': None,
    'AUDIENCE': None,
    'ISSUER': None,
    
    'AUTH_HEADER_TYPES': ('Bearer',),
    'AUTH_HEADER_NAME': 'HTTP_AUTHORIZATION',
    'USER_ID_FIELD': 'id',
    'USER_ID_CLAIM': 'user_id',
    
    'AUTH_TOKEN_CLASSES': ('rest_framework_simplejwt.tokens.AccessToken',),
    'TOKEN_TYPE_CLAIM': 'token_type',
    
    'JTI_CLAIM': 'jti',
    'SLIDING_TOKEN_REFRESH_EXP_CLAIM': 'refresh_exp',
    'SLIDING_TOKEN_LIFETIME': timedelta(minutes=5),
    'SLIDING_TOKEN_REFRESH_LIFETIME': timedelta(days=30),
}
```

## 2.2 Custom Token Serializer

```python
# accounts/serializers.py
from rest_framework import serializers
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework_simplejwt.tokens import RefreshToken
from django.contrib.auth import authenticate
from sessions.models import Session, Device
from django.conf import settings
import uuid

class EnhancedTokenObtainPairSerializer(TokenObtainPairSerializer):
    """JWT with session tracking and token versioning"""
    
    # Additional fields for login
    install_id = serializers.UUIDField(required=False, allow_null=True)
    platform = serializers.CharField(required=False, default='web')
    app_version = serializers.CharField(required=False, default='1.0.0')
    device_name = serializers.CharField(required=False, allow_blank=True)
    
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        
        # Add custom claims
        token['tver'] = user.token_version  # Token version for instant revocation
        token['status'] = user.status
        token['username'] = user.username
        token['email'] = user.email
        
        # Add roles and permissions for your tenant system
        token['roles'] = list(user.groups.values_list('name', flat=True))
        token['perms'] = sorted(list(user.get_all_permissions()))
        
        return token
    
    def validate(self, attrs):
        # Custom validation
        username = attrs.get('username')
        password = attrs.get('password')
        
        # Allow login with email or username
        from django.db.models import Q
        from accounts.models import User
        
        try:
            user = User.objects.get(Q(username=username) | Q(email=username))
        except User.DoesNotExist:
            raise serializers.ValidationError({
                'code': 'INVALID_CREDENTIALS',
                'message': 'Invalid username or password'
            })
        
        # Authenticate
        if not user.check_password(password):
            raise serializers.ValidationError({
                'code': 'INVALID_CREDENTIALS',
                'message': 'Invalid username or password'
            })
        
        # Check user status
        if user.status != 'active':
            error_map = {
                'banned': f'Account banned: {user.banned_reason or "Contact support"}',
                'deleted': 'This account no longer exists',
                'disabled': 'Account disabled. Contact support.'
            }
            raise serializers.ValidationError({
                'code': 'ACCOUNT_DISABLED',
                'message': error_map.get(user.status, 'Account not active')
            })
        
        # Create or update device
        device = None
        install_id = self.initial_data.get('install_id')
        if install_id:
            device, created = Device.objects.update_or_create(
                install_id=install_id,
                user=user,
                defaults={
                    'platform': self.initial_data.get('platform', 'web'),
                    'app_version': self.initial_data.get('app_version', '1.0.0'),
                    'device_name': self.initial_data.get('device_name', ''),
                }
            )
        
        # Create session
        request = self.context.get('request')
        session, refresh_token_str = Session.create_session(user, request, device)
        
        # Generate tokens
        refresh = self.get_token(user)
        access = refresh.access_token
        
        # Add session ID to tokens
        refresh['sid'] = str(session.id)
        access['sid'] = str(session.id)
        
        # Add JTI for access token denylisting
        access['jti'] = str(uuid.uuid4())
        
        # Store the actual refresh token string (unhashed) to return
        self._refresh_token_str = refresh_token_str
        self._session = session
        
        return {
            'access': str(access),
            'refresh': self._refresh_token_str,
            'session_id': str(session.id),
            'expires_in': settings.SIMPLE_JWT['ACCESS_TOKEN_LIFETIME'].total_seconds(),
            'user': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
                'email_verified': user.email_verified,
                'phone_verified': user.phone_verified,
            }
        }
```

## 2.3 Session Enforcement Middleware

```python
# sessions/middleware.py
from django.http import JsonResponse
from django.contrib.auth import get_user_model
from sessions.models import Session
import jwt
from django.conf import settings

User = get_user_model()

class SessionEnforcementMiddleware:
    """Enforce account status and session validity on every request"""
    
    def __init__(self, get_response):
        self.get_response = get_response
        self.exempt_paths = [
            '/api/auth/login',
            '/api/auth/register', 
            '/api/auth/refresh',
            '/api/auth/otp/',
            '/app/version',
            '/api/v1/auth/forms',
            '/admin/',
            '/swagger/',
            '/redoc/',
        ]
        
    def __call__(self, request):
        # Skip exempt paths
        if any(request.path.startswith(p) for p in self.exempt_paths):
            return self.get_response(request)
        
        # Skip if no auth header
        auth_header = request.headers.get('Authorization', '')
        if not auth_header.startswith('Bearer '):
            return self.get_response(request)
            
        try:
            token = auth_header.split(' ')[1]
            
            # Decode without verification to get claims
            unverified = jwt.decode(
                token, 
                options={"verify_signature": False}
            )
            
            user_id = unverified.get('user_id')
            if not user_id:
                return self.get_response(request)
            
            # Load user
            try:
                user = User.objects.get(id=user_id)
            except User.DoesNotExist:
                return JsonResponse({
                    'code': 'INVALID_TOKEN',
                    'message': 'User not found'
                }, status=401)
            
            # Check user status
            if user.status != 'active':
                return JsonResponse({
                    'code': 'ACCOUNT_DISABLED',
                    'message': self._get_status_message(user)
                }, status=403)
            
            # Check token version
            token_version = unverified.get('tver')
            if token_version and token_version != user.token_version:
                return JsonResponse({
                    'code': 'TOKEN_REVOKED',
                    'message': 'Session ended. Please sign in again.'
                }, status=401)
            
            # Check session validity
            session_id = unverified.get('sid')
            if session_id:
                try:
                    session = Session.objects.get(id=session_id)
                    if not session.is_valid():
                        return JsonResponse({
                            'code': 'TOKEN_REVOKED',
                            'message': 'Session expired or revoked.'
                        }, status=401)
                except Session.DoesNotExist:
                    return JsonResponse({
                        'code': 'TOKEN_REVOKED',
                        'message': 'Invalid session.'
                    }, status=401)
                    
        except jwt.ExpiredSignatureError:
            return JsonResponse({
                'code': 'TOKEN_EXPIRED',
                'message': 'Token expired. Please refresh.'
            }, status=401)
        except Exception as e:
            # Let DRF handle other auth errors
            pass
            
        return self.get_response(request)
    
    def _get_status_message(self, user):
        if user.status == 'banned':
            return f'Account banned: {user.banned_reason or "Contact support"}'
        elif user.status == 'deleted':
            return 'This account no longer exists'
        elif user.status == 'disabled':
            return 'Account disabled. Contact support.'
        return 'Account not active'
```

## 2.4 Add Middleware to Settings

```python
# authstack/settings.py

MIDDLEWARE = [
    'django.middleware.security.SecurityMiddleware',
    'django.contrib.sessions.middleware.SessionMiddleware',
    'corsheaders.middleware.CorsMiddleware',
    'django.middleware.common.CommonMiddleware',
    'django.middleware.csrf.CsrfViewMiddleware',
    'django.contrib.auth.middleware.AuthenticationMiddleware',
    'django.contrib.messages.middleware.MessageMiddleware',
    'django.middleware.clickjacking.XFrameOptionsMiddleware',
    'sessions.middleware.SessionEnforcementMiddleware',  # Add this
]
```

## 2.5 Login View

```python
# accounts/views.py
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from accounts.serializers import EnhancedTokenObtainPairSerializer

@api_view(['POST'])
@permission_classes([AllowAny])
def login_view(request):
    """Enhanced login with session tracking"""
    serializer = EnhancedTokenObtainPairSerializer(
        data=request.data,
        context={'request': request}
    )
    
    if serializer.is_valid():
        return Response(serializer.validated_data, status=status.HTTP_200_OK)
    
    # Format error response
    errors = serializer.errors
    if 'non_field_errors' in errors:
        error = errors['non_field_errors'][0]
        if isinstance(error, dict):
            return Response(error, status=status.HTTP_400_BAD_REQUEST)
    
    return Response({
        'code': 'VALIDATION_ERROR',
        'message': 'Invalid input',
        'errors': errors
    }, status=status.HTTP_400_BAD_REQUEST)
```

## 2.6 Current User Endpoint

```python
# accounts/views.py
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def current_user_view(request):
    """Get current user info (quick status check)"""
    user = request.user
    
    return Response({
        'id': str(user.id),
        'username': user.username,
        'email': user.email,
        'status': user.status,
        'email_verified': user.email_verified,
        'phone_verified': user.phone_verified,
        'phone': user.phone_e164,
        'roles': list(user.groups.values_list('name', flat=True)),
        'token_version': user.token_version,
    })
```

## 2.7 Update URLs

```python
# accounts/urls.py
from django.urls import path
from . import views

urlpatterns = [
    path('login/', views.login_view, name='login'),
    path('me/', views.current_user_view, name='current_user'),
    # Add more endpoints in next parts
]
```

```python
# authstack/urls.py
from django.urls import path, include

urlpatterns = [
    # ... existing paths
    path('api/auth/', include('accounts.urls')),
]
```

## Testing

### Test enhanced login
```bash
# Test login with session creation
curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "username": "testuser",
    "password": "testpass123",
    "install_id": "550e8400-e29b-41d4-a716-446655440000",
    "platform": "ios",
    "app_version": "1.0.0"
  }'

# Response should include:
# {
#   "access": "eyJ...",
#   "refresh": "...",
#   "session_id": "...",
#   "expires_in": 300,
#   "user": {...}
# }
```

### Test token enforcement
```python
# Django shell test
from accounts.models import User

# Ban a user and test token invalidation
user = User.objects.get(username='testuser')
old_version = user.token_version

user.ban('Test reason')
assert user.token_version == old_version + 1

# Old tokens should now be rejected with TOKEN_REVOKED
```

## Next Steps

✅ Enhanced JWT with token versioning  
✅ Session tracking in tokens
✅ Middleware for status enforcement
✅ Login endpoint with session creation

Continue to [Part 3: Refresh Token Rotation](./part3-refresh-rotation.md)
