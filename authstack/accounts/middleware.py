from django.utils.deprecation import MiddlewareMixin
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from django.http import JsonResponse
from .models import UserSession
import logging

logger = logging.getLogger(__name__)


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

            # Prefer session_id for deterministic lookup
            session_id = token.get('session_id')
            if session_id:
                try:
                    session = UserSession.objects.get(id=session_id)
                    print(f"[SessionRevocationMiddleware] session_id={session_id} active={session.is_active}")
                    if not session.is_active:
                        return JsonResponse({'error': 'Session has been revoked', 'code': 'SESSION_REVOKED'}, status=401)
                except UserSession.DoesNotExist:
                    print(f"[SessionRevocationMiddleware] No session with id={session_id}")
                    # If token claims a non-existent session, reject for safety
                    return JsonResponse({'error': 'Invalid session', 'code': 'SESSION_NOT_FOUND'}, status=401)
                return None

            # Fallback to JTI mapping
            jti = token.get('jti')
            if not jti:
                return None
            try:
                session = UserSession.objects.get(access_token_jti=jti)
                print(f"[SessionRevocationMiddleware] Fallback JTI={jti} active={session.is_active}")
                if not session.is_active:
                    return JsonResponse({'error': 'Session has been revoked', 'code': 'SESSION_REVOKED'}, status=401)
            except UserSession.DoesNotExist:
                print(f"[SessionRevocationMiddleware] No session for JTI={jti}")
                pass

        except (TokenError, IndexError):
            # Invalid token format, let the auth middleware handle it
            pass
            
        return None
