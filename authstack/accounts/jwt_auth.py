"""Custom JWT authentication with token versioning and refresh token rotation"""
import hashlib
import secrets
from datetime import datetime, timedelta
from typing import Optional

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer

from accounts.models import UserSession

User = get_user_model()


class TokenVersionMixin:
    """Mixin to add token version validation"""
    
    @classmethod
    def get_token(cls, user):
        token = super().get_token(user)
        # Add custom claims
        token['token_version'] = getattr(user, 'token_version', 1)
        token['user_id'] = str(user.id)
        return token
    
    def validate(self, attrs):
        data = super().validate(attrs)
        
        # Check if user has token_version attribute
        if hasattr(self.user, 'token_version'):
            refresh = self.get_token(self.user)
            data['refresh'] = str(refresh)
            data['access'] = str(refresh.access_token)
        
        return data


class CustomTokenObtainPairSerializer(TokenVersionMixin, TokenObtainPairSerializer):
    """Custom serializer with token versioning"""
    
    def validate(self, attrs):
        data = super().validate(attrs)
        
        # Create or update session
        request = self.context.get('request')
        if request:
            # Get tenant_id from request
            tenant_id = request.META.get('HTTP_X_TENANT_ID', 'ontime')
            
            # Generate device ID if not provided
            device_id = request.META.get('HTTP_X_DEVICE_ID', '')
            if not device_id:
                device_id = hashlib.sha256(
                    f"{request.META.get('HTTP_USER_AGENT', '')}:{request.META.get('REMOTE_ADDR', '')}".encode()
                ).hexdigest()[:32]
            
            # Extract refresh token JTI and add tenant_id
            refresh_token = RefreshToken(data['refresh'])
            jti = refresh_token.payload.get('jti', '')
            
            # Add tenant_id to both tokens
            refresh_token['tenant_id'] = tenant_id
            refresh_token.access_token['tenant_id'] = tenant_id
            
            # Create session
            session = UserSession.objects.create(
                user=self.user,
                device_id=device_id,
                device_name=request.META.get('HTTP_X_DEVICE_NAME', ''),
                device_type=request.META.get('HTTP_X_DEVICE_TYPE', 'unknown'),
                ip_address=request.META.get('REMOTE_ADDR', ''),
                user_agent=request.META.get('HTTP_USER_AGENT', '')[:500],
                refresh_token_jti=jti,
                expires_at=timezone.now() + timedelta(days=7)
            )
            
            # Store session ID in token
            refresh_token['session_id'] = str(session.id)
            data['refresh'] = str(refresh_token)
            data['access'] = str(refresh_token.access_token)
        
        return data


class CustomJWTAuthentication(JWTAuthentication):
    """JWT authentication with token version checking"""
    
    def get_validated_token(self, raw_token):
        """Validate token and check version"""
        validated_token = super().get_validated_token(raw_token)
        
        # Get user and check token version
        user_id = validated_token.get('user_id')
        token_version = validated_token.get('token_version')
        
        if user_id:
            try:
                user = User.objects.get(id=user_id)
                
                # Check if user is active
                if hasattr(user, 'status') and user.status != 'active':
                    raise InvalidToken('User account is not active')
                
                # Check token version if both token and user have it
                if token_version is not None and hasattr(user, 'token_version'):
                    # Refresh user from DB to get latest token_version
                    user.refresh_from_db()
                    user_token_version = getattr(user, 'token_version', 1)
                    if user_token_version != token_version:
                        raise InvalidToken('Token has been revoked')
                    
            except User.DoesNotExist:
                raise InvalidToken('User not found')
        
        return validated_token


class RefreshTokenRotation:
    """Handle refresh token rotation for enhanced security"""
    
    @staticmethod
    def rotate_refresh_token(old_refresh_token: str, request=None) -> dict:
        """
        Rotate refresh token and return new tokens
        
        Args:
            old_refresh_token: The current refresh token
            request: The HTTP request object
            
        Returns:
            dict with new 'access' and 'refresh' tokens
        """
        try:
            # Parse old token
            old_token = RefreshToken(old_refresh_token)
            
            # Get session
            session_id = old_token.get('session_id')
            jti = old_token.get('jti')
            
            if session_id:
                try:
                    session = UserSession.objects.get(
                        id=session_id,
                        refresh_token_jti=jti,
                        is_active=True
                    )
                    
                    # Check if session is expired
                    if session.expires_at < timezone.now():
                        session.revoke('expired')
                        raise InvalidToken('Session has expired')
                    
                    # Get user
                    user = session.user
                    
                    # Create new token
                    new_token = RefreshToken.for_user(user)
                    new_token['session_id'] = str(session.id)
                    new_token['token_version'] = getattr(user, 'token_version', 1)
                    
                    # Preserve tenant_id from old token
                    tenant_id = old_token.get('tenant_id')
                    if tenant_id:
                        new_token['tenant_id'] = tenant_id
                        new_token.access_token['tenant_id'] = tenant_id
                    
                    # Update session with new JTI
                    session.refresh_token_jti = new_token['jti']
                    session.last_activity = timezone.now()
                    session.save()
                    
                    return {
                        'access': str(new_token.access_token),
                        'refresh': str(new_token)
                    }
                    
                except UserSession.DoesNotExist:
                    raise InvalidToken('Session not found or inactive')
            else:
                # Fallback for tokens without session
                user_id = old_token.get('user_id')
                user = User.objects.get(id=user_id)
                
                # Check token version
                token_version = old_token.get('token_version', 1)
                if hasattr(user, 'token_version') and user.token_version != token_version:
                    raise InvalidToken('Token has been revoked')
                
                # Create new token
                new_token = RefreshToken.for_user(user)
                new_token['token_version'] = getattr(user, 'token_version', 1)
                
                return {
                    'access': str(new_token.access_token),
                    'refresh': str(new_token)
                }
                
        except TokenError as e:
            raise InvalidToken(f'Token is invalid or expired: {str(e)}')
