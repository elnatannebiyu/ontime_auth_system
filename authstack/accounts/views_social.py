from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from django.conf import settings
from django.utils import timezone
from django.contrib.auth import get_user_model

from accounts.social_auth import SocialAuthService
from accounts.models import SocialAccount
from accounts.jwt_auth import CustomTokenObtainPairSerializer
from user_sessions.models import Session

User = get_user_model()


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
            'error': 'Provider and token required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    if provider not in ['google', 'apple']:
        return Response({
            'error': f'Unsupported provider: {provider}'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Verify token based on provider
    if provider == 'google':
        success, info = SocialAuthService.verify_google_token(token)
    elif provider == 'apple':
        success, info = SocialAuthService.verify_apple_token(token, nonce)
    
    if not success:
        return Response({
            'error': info.get('error', 'Authentication failed')
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
                last_name=user_data.get('last_name', info.get('family_name', ''))
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
    if not user.is_active:
        return Response({
            'error': 'Account is disabled'
        }, status=status.HTTP_403_FORBIDDEN)
    
    # Create session using the Session.create_session method
    session, refresh_token_plain = Session.create_session(user=user, request=request)
    
    # Generate JWT tokens
    serializer = CustomTokenObtainPairSerializer()
    token = serializer.get_token(user)
    refresh = token
    access = refresh.access_token
    
    # Add session info to tokens
    refresh['sid'] = str(session.id)
    access['sid'] = str(session.id)
    
    # Add tenant_id if available
    if hasattr(request, 'tenant') and request.tenant:
        refresh['tenant_id'] = str(request.tenant.id)
        access['tenant_id'] = str(request.tenant.id)
    
    # Set refresh token cookie
    response = Response({
        'access': str(access),
        'refresh': str(refresh),
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
        'is_new_user': social_account.created_at == social_account.last_login
    }, status=status.HTTP_200_OK)
    
    # Set HTTP-only cookie for refresh token
    response.set_cookie(
        key='refresh_token',
        value=refresh_token_plain,
        max_age=int(settings.SIMPLE_JWT['REFRESH_TOKEN_LIFETIME'].total_seconds()),
        httponly=True,
        secure=not settings.DEBUG,
        samesite='Lax'
    )
    
    return response


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def link_social_account_view(request):
    """Link social account to existing user"""
    provider = request.data.get('provider', '').lower()
    token = request.data.get('token')
    nonce = request.data.get('nonce')
    
    if not provider or not token:
        return Response({
            'error': 'Provider and token required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Verify token
    if provider == 'google':
        success, info = SocialAuthService.verify_google_token(token)
    elif provider == 'apple':
        success, info = SocialAuthService.verify_apple_token(token, nonce)
    else:
        return Response({
            'error': f'Unsupported provider: {provider}'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    if not success:
        return Response({
            'error': info.get('error', 'Authentication failed')
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
                'error': 'This social account is linked to another user'
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
                'error': 'Cannot unlink last authentication method. Set a password first.'
            }, status=status.HTTP_400_BAD_REQUEST)
    
    # Delete social account
    deleted = request.user.social_accounts.filter(provider=provider).delete()
    
    if deleted[0] == 0:
        return Response({
            'error': f'{provider.title()} account not linked'
        }, status=status.HTTP_404_NOT_FOUND)
    
    return Response({
        'message': f'{provider.title()} account unlinked successfully'
    }, status=status.HTTP_200_OK)
