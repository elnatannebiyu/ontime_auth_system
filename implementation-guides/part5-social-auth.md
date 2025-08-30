# Part 5: Social Authentication

## Overview
Implement OAuth2 social authentication with Google, Apple, and Facebook providers.

## 5.1 Install Dependencies

```bash
pip install python-social-auth[django] PyJWT cryptography
```

## 5.2 Social Auth Models

```python
# accounts/models.py (extend existing)
class SocialAccount(models.Model):
    """Store social auth provider data"""
    
    PROVIDER_CHOICES = [
        ('google', 'Google'),
        ('apple', 'Apple'),
        ('facebook', 'Facebook'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='social_accounts')
    
    provider = models.CharField(max_length=20, choices=PROVIDER_CHOICES)
    provider_id = models.CharField(max_length=255, db_index=True)
    
    # OAuth data
    access_token = models.TextField(blank=True)
    refresh_token = models.TextField(blank=True)
    token_expires_at = models.DateTimeField(null=True, blank=True)
    
    # Profile data
    email = models.EmailField(blank=True)
    name = models.CharField(max_length=255, blank=True)
    picture_url = models.URLField(blank=True)
    extra_data = models.JSONField(default=dict)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)
    last_login = models.DateTimeField(null=True, blank=True)
    
    class Meta:
        db_table = 'social_accounts'
        unique_together = [['provider', 'provider_id']]
        indexes = [
            models.Index(fields=['provider', 'provider_id']),
        ]
```

## 5.3 Social Auth Service

```python
# accounts/social_auth.py
import jwt
import requests
import json
from datetime import datetime, timedelta
from django.conf import settings
from django.utils import timezone
from typing import Dict, Tuple, Optional
import logging

logger = logging.getLogger(__name__)

class SocialAuthService:
    """Handle social authentication providers"""
    
    @staticmethod
    def verify_google_token(id_token: str) -> Tuple[bool, Dict]:
        """Verify Google ID token"""
        try:
            # Decode without verification first to get kid
            unverified = jwt.decode(id_token, options={"verify_signature": False})
            
            # Get Google's public keys
            response = requests.get('https://www.googleapis.com/oauth2/v3/certs')
            keys = response.json()['keys']
            
            # Find the key with matching kid
            header = jwt.get_unverified_header(id_token)
            key = next((k for k in keys if k['kid'] == header['kid']), None)
            
            if not key:
                return False, {'error': 'Invalid key ID'}
            
            # Verify token
            decoded = jwt.decode(
                id_token,
                key=key,
                algorithms=['RS256'],
                audience=settings.GOOGLE_CLIENT_ID,
                issuer=['accounts.google.com', 'https://accounts.google.com']
            )
            
            # Extract user info
            user_info = {
                'provider_id': decoded['sub'],
                'email': decoded.get('email'),
                'email_verified': decoded.get('email_verified', False),
                'name': decoded.get('name'),
                'picture': decoded.get('picture'),
                'given_name': decoded.get('given_name'),
                'family_name': decoded.get('family_name'),
            }
            
            return True, user_info
            
        except jwt.ExpiredSignatureError:
            return False, {'error': 'Token expired'}
        except jwt.InvalidTokenError as e:
            return False, {'error': f'Invalid token: {str(e)}'}
        except Exception as e:
            logger.error(f"Google token verification failed: {e}")
            return False, {'error': 'Verification failed'}
    
    @staticmethod
    def verify_apple_token(id_token: str, nonce: str = None) -> Tuple[bool, Dict]:
        """Verify Apple ID token"""
        try:
            # Get Apple's public keys
            response = requests.get('https://appleid.apple.com/auth/keys')
            keys = response.json()['keys']
            
            # Get the matching key
            header = jwt.get_unverified_header(id_token)
            key = next((k for k in keys if k['kid'] == header['kid']), None)
            
            if not key:
                return False, {'error': 'Invalid key ID'}
            
            # Convert to PEM format
            from jwt.algorithms import RSAAlgorithm
            public_key = RSAAlgorithm.from_jwk(json.dumps(key))
            
            # Verify token
            decoded = jwt.decode(
                id_token,
                public_key,
                algorithms=['RS256'],
                audience=settings.APPLE_CLIENT_ID,
                issuer='https://appleid.apple.com'
            )
            
            # Verify nonce if provided
            if nonce and decoded.get('nonce') != nonce:
                return False, {'error': 'Invalid nonce'}
            
            # Extract user info
            user_info = {
                'provider_id': decoded['sub'],
                'email': decoded.get('email'),
                'email_verified': decoded.get('email_verified', False),
                'is_private_email': decoded.get('is_private_email', False),
            }
            
            return True, user_info
            
        except jwt.ExpiredSignatureError:
            return False, {'error': 'Token expired'}
        except jwt.InvalidTokenError as e:
            return False, {'error': f'Invalid token: {str(e)}'}
        except Exception as e:
            logger.error(f"Apple token verification failed: {e}")
            return False, {'error': 'Verification failed'}
    
    @staticmethod
    def verify_facebook_token(access_token: str) -> Tuple[bool, Dict]:
        """Verify Facebook access token"""
        try:
            # Verify token with Facebook
            app_token = f"{settings.FACEBOOK_APP_ID}|{settings.FACEBOOK_APP_SECRET}"
            
            # Debug token
            debug_url = f"https://graph.facebook.com/debug_token"
            debug_params = {
                'input_token': access_token,
                'access_token': app_token
            }
            
            debug_response = requests.get(debug_url, params=debug_params)
            debug_data = debug_response.json()
            
            if 'error' in debug_data:
                return False, {'error': debug_data['error']['message']}
            
            token_data = debug_data.get('data', {})
            
            # Check if token is valid
            if not token_data.get('is_valid'):
                return False, {'error': 'Invalid token'}
            
            # Check app ID
            if token_data.get('app_id') != settings.FACEBOOK_APP_ID:
                return False, {'error': 'Token for wrong app'}
            
            # Get user info
            user_url = f"https://graph.facebook.com/v12.0/me"
            user_params = {
                'fields': 'id,name,email,picture',
                'access_token': access_token
            }
            
            user_response = requests.get(user_url, params=user_params)
            user_data = user_response.json()
            
            if 'error' in user_data:
                return False, {'error': user_data['error']['message']}
            
            # Extract user info
            user_info = {
                'provider_id': user_data['id'],
                'email': user_data.get('email'),
                'name': user_data.get('name'),
                'picture': user_data.get('picture', {}).get('data', {}).get('url'),
            }
            
            return True, user_info
            
        except Exception as e:
            logger.error(f"Facebook token verification failed: {e}")
            return False, {'error': 'Verification failed'}
```

## 5.4 Social Auth Views

```python
# accounts/views.py (add to existing)
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from accounts.social_auth import SocialAuthService
from accounts.models import User, SocialAccount
from sessions.models import Session, Device

@api_view(['POST'])
@permission_classes([AllowAny])
def social_login_view(request):
    """Login or register with social provider"""
    provider = request.data.get('provider', '').lower()
    token = request.data.get('token')  # ID token or access token
    nonce = request.data.get('nonce')  # For Apple
    
    # Additional user data for registration
    user_data = request.data.get('user_data', {})
    
    if not provider or not token:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Provider and token required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    if provider not in ['google', 'apple', 'facebook']:
        return Response({
            'code': 'INVALID_PROVIDER',
            'message': f'Provider {provider} not supported'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Verify token based on provider
    if provider == 'google':
        success, info = SocialAuthService.verify_google_token(token)
    elif provider == 'apple':
        success, info = SocialAuthService.verify_apple_token(token, nonce)
    elif provider == 'facebook':
        success, info = SocialAuthService.verify_facebook_token(token)
    
    if not success:
        return Response({
            'code': 'AUTH_FAILED',
            'message': info.get('error', 'Authentication failed')
        }, status=status.HTTP_401_UNAUTHORIZED)
    
    # Find or create social account
    try:
        social_account = SocialAccount.objects.get(
            provider=provider,
            provider_id=info['provider_id']
        )
        user = social_account.user
        
        # Update social account info
        social_account.email = info.get('email', '')
        social_account.name = info.get('name', '')
        social_account.picture_url = info.get('picture', '')
        social_account.last_login = timezone.now()
        social_account.save()
        
    except SocialAccount.DoesNotExist:
        # Check if user with email exists
        email = info.get('email')
        user = None
        
        if email:
            user = User.objects.filter(email=email).first()
        
        if not user:
            # Create new user
            username = email.split('@')[0] if email else f"{provider}_{info['provider_id']}"
            
            # Ensure unique username
            base_username = username
            counter = 1
            while User.objects.filter(username=username).exists():
                username = f"{base_username}{counter}"
                counter += 1
            
            user = User.objects.create(
                username=username,
                email=email or '',
                first_name=user_data.get('first_name', info.get('given_name', '')),
                last_name=user_data.get('last_name', info.get('family_name', '')),
                email_verified=info.get('email_verified', False),
                status='active'
            )
            
            # Set unusable password for social auth users
            user.set_unusable_password()
            user.save()
        
        # Create social account
        social_account = SocialAccount.objects.create(
            user=user,
            provider=provider,
            provider_id=info['provider_id'],
            email=info.get('email', ''),
            name=info.get('name', ''),
            picture_url=info.get('picture', ''),
            extra_data=info
        )
    
    # Check user status
    if user.status != 'active':
        return Response({
            'code': 'ACCOUNT_DISABLED',
            'message': 'Account is not active'
        }, status=status.HTTP_403_FORBIDDEN)
    
    # Create session
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
    
    session, refresh_token = Session.create_session(user, request, device)
    
    # Generate tokens
    from accounts.serializers import EnhancedTokenObtainPairSerializer
    refresh = EnhancedTokenObtainPairSerializer.get_token(user)
    access = refresh.access_token
    
    # Add session info
    refresh['sid'] = str(session.id)
    access['sid'] = str(session.id)
    
    return Response({
        'access': str(access),
        'refresh': refresh_token,
        'session_id': str(session.id),
        'expires_in': settings.SIMPLE_JWT['ACCESS_TOKEN_LIFETIME'].total_seconds(),
        'user': {
            'id': str(user.id),
            'username': user.username,
            'email': user.email,
            'first_name': user.first_name,
            'last_name': user.last_name,
            'picture': social_account.picture_url,
            'provider': provider,
        },
        'is_new_user': social_account.created_at == social_account.updated_at
    }, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def link_social_account_view(request):
    """Link social account to existing user"""
    provider = request.data.get('provider', '').lower()
    token = request.data.get('token')
    nonce = request.data.get('nonce')
    
    if not provider or not token:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Provider and token required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Verify token
    if provider == 'google':
        success, info = SocialAuthService.verify_google_token(token)
    elif provider == 'apple':
        success, info = SocialAuthService.verify_apple_token(token, nonce)
    elif provider == 'facebook':
        success, info = SocialAuthService.verify_facebook_token(token)
    else:
        return Response({
            'code': 'INVALID_PROVIDER',
            'message': f'Provider {provider} not supported'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    if not success:
        return Response({
            'code': 'AUTH_FAILED',
            'message': info.get('error', 'Authentication failed')
        }, status=status.HTTP_401_UNAUTHORIZED)
    
    # Check if already linked
    existing = SocialAccount.objects.filter(
        provider=provider,
        provider_id=info['provider_id']
    ).first()
    
    if existing:
        if existing.user == request.user:
            return Response({
                'message': 'Account already linked'
            }, status=status.HTTP_200_OK)
        else:
            return Response({
                'code': 'ALREADY_LINKED',
                'message': 'This social account is linked to another user'
            }, status=status.HTTP_400_BAD_REQUEST)
    
    # Link account
    social_account = SocialAccount.objects.create(
        user=request.user,
        provider=provider,
        provider_id=info['provider_id'],
        email=info.get('email', ''),
        name=info.get('name', ''),
        picture_url=info.get('picture', ''),
        extra_data=info
    )
    
    return Response({
        'message': f'{provider.title()} account linked successfully',
        'provider': provider,
        'email': social_account.email,
        'name': social_account.name
    }, status=status.HTTP_200_OK)

@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def unlink_social_account_view(request, provider):
    """Unlink social account"""
    # Check if user has password set
    if not request.user.has_usable_password():
        # Check if this is the only auth method
        social_count = request.user.social_accounts.count()
        if social_count <= 1:
            return Response({
                'code': 'LAST_AUTH_METHOD',
                'message': 'Cannot unlink last authentication method. Set a password first.'
            }, status=status.HTTP_400_BAD_REQUEST)
    
    # Delete social account
    deleted = request.user.social_accounts.filter(provider=provider).delete()
    
    if deleted[0] == 0:
        return Response({
            'code': 'NOT_FOUND',
            'message': f'{provider.title()} account not linked'
        }, status=status.HTTP_404_NOT_FOUND)
    
    return Response({
        'message': f'{provider.title()} account unlinked successfully'
    }, status=status.HTTP_200_OK)
```

## 5.5 Settings Configuration

```python
# authstack/settings.py

# Social Auth Settings
GOOGLE_CLIENT_ID = os.environ.get('GOOGLE_CLIENT_ID', '')
GOOGLE_CLIENT_SECRET = os.environ.get('GOOGLE_CLIENT_SECRET', '')

APPLE_CLIENT_ID = os.environ.get('APPLE_CLIENT_ID', '')
APPLE_TEAM_ID = os.environ.get('APPLE_TEAM_ID', '')
APPLE_KEY_ID = os.environ.get('APPLE_KEY_ID', '')
APPLE_PRIVATE_KEY = os.environ.get('APPLE_PRIVATE_KEY', '')

FACEBOOK_APP_ID = os.environ.get('FACEBOOK_APP_ID', '')
FACEBOOK_APP_SECRET = os.environ.get('FACEBOOK_APP_SECRET', '')

# Social auth configuration
SOCIAL_AUTH_PIPELINE = (
    'social_core.pipeline.social_auth.social_details',
    'social_core.pipeline.social_auth.social_uid',
    'social_core.pipeline.social_auth.social_user',
    'social_core.pipeline.user.get_username',
    'social_core.pipeline.user.create_user',
    'social_core.pipeline.social_auth.associate_user',
    'social_core.pipeline.social_auth.load_extra_data',
    'social_core.pipeline.user.user_details',
)
```

## 5.6 Update URLs

```python
# accounts/urls.py (add to existing)
urlpatterns = [
    # ... existing URLs
    path('social/login/', views.social_login_view, name='social_login'),
    path('social/link/', views.link_social_account_view, name='link_social'),
    path('social/unlink/<str:provider>/', views.unlink_social_account_view, name='unlink_social'),
]
```

## Testing

### Test Google login
```bash
# Get a Google ID token from frontend first
curl -X POST http://localhost:8000/api/auth/social/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "google",
    "token": "GOOGLE_ID_TOKEN",
    "install_id": "device-uuid"
  }'
```

### Test Apple login
```bash
curl -X POST http://localhost:8000/api/auth/social/login/ \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "apple",
    "token": "APPLE_ID_TOKEN",
    "nonce": "NONCE_VALUE"
  }'
```

### Test linking account
```bash
curl -X POST http://localhost:8000/api/auth/social/link/ \
  -H "Authorization: Bearer ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{
    "provider": "facebook",
    "token": "FB_ACCESS_TOKEN"
  }'
```

## Frontend OAuth Setup

### Google Sign-In
1. Create OAuth 2.0 Client ID at https://console.cloud.google.com
2. Add authorized origins and redirect URIs
3. Use Google Sign-In SDK in Flutter

### Apple Sign-In
1. Enable Sign in with Apple in App ID configuration
2. Create Service ID for web
3. Configure Return URLs
4. Use sign_in_with_apple package in Flutter

### Facebook Login
1. Create Facebook App at https://developers.facebook.com
2. Add platform configurations
3. Enable Facebook Login product
4. Use flutter_facebook_auth package

## Security Notes

1. **Token Verification**: Always verify tokens server-side
2. **HTTPS Required**: OAuth requires secure connections
3. **Nonce for Apple**: Prevent replay attacks
4. **Account Linking**: Require authentication to link accounts
5. **Email Verification**: Trust provider's email verification status

## Next Steps

✅ Social account model
✅ Token verification for Google, Apple, Facebook
✅ Social login and registration
✅ Account linking/unlinking
✅ Integration with session management

Continue to [Part 6: Dynamic Forms API](./part6-dynamic-forms.md)
