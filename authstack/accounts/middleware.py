from django.utils.deprecation import MiddlewareMixin
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from django.http import JsonResponse
from .models import UserSession


class SessionRevocationMiddleware(MiddlewareMixin):
    """Check if the session has been revoked on every authenticated request"""
    
    def process_request(self, request):
        # Skip for non-API routes
        if not request.path.startswith('/api/'):
            return None
            
        # Get the authorization header
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        if not auth_header.startswith('Bearer '):
            return None
            
        try:
            # Extract and decode the token
            token_str = auth_header.split(' ')[1]
            token = AccessToken(token_str)
            
            # Get the JTI from the token
            jti = token.get('jti')
            if not jti:
                return None
                
            # Check if this session has been revoked
            try:
                session = UserSession.objects.get(
                    access_token_jti=jti,
                    is_active=False  # Check if revoked
                )
                # Session has been revoked
                return JsonResponse({
                    'error': 'Session has been revoked',
                    'code': 'SESSION_REVOKED'
                }, status=401)
            except UserSession.DoesNotExist:
                # Session is either active or doesn't exist (normal flow)
                pass
                
        except (TokenError, IndexError):
            # Invalid token format, let the auth middleware handle it
            pass
            
        return None
