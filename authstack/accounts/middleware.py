from django.utils.deprecation import MiddlewareMixin
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from django.http import JsonResponse
from user_sessions.models import Session as RefreshSession
from .models import UserSession as LegacySession
import logging

logger = logging.getLogger(__name__)


class SessionRevocationMiddleware(MiddlewareMixin):
    """Check if the session has been revoked on every authenticated request"""
    
    def process_request(self, request):
        # Skip for non-API routes
        if not request.path.startswith('/api/'):
            return None

        # Do not enforce revocation on unauthenticated endpoints
        _skip_paths = {
            '/api/social/login/',
            '/api/token/',
            '/api/token/refresh/',
            '/api/register/',
        }
        if request.path in _skip_paths:
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
                # Preferred: new refresh session backend
                try:
                    session = RefreshSession.objects.get(id=session_id)
                    print(f"[SessionRevocationMiddleware] session_id={session_id} revoked_at={session.revoked_at}")
                    if getattr(session, 'revoked_at', None):
                        return JsonResponse({'error': 'Session has been revoked', 'code': 'SESSION_REVOKED'}, status=401)
                    return None
                except RefreshSession.DoesNotExist:
                    # Fallback: legacy accounts.UserSession
                    try:
                        legacy = LegacySession.objects.get(id=session_id)
                        print(f"[SessionRevocationMiddleware] legacy session_id={session_id} is_active={legacy.is_active}")
                        if not legacy.is_active:
                            return JsonResponse({'error': 'Session has been revoked', 'code': 'SESSION_REVOKED'}, status=401)
                        return None
                    except LegacySession.DoesNotExist:
                        print(f"[SessionRevocationMiddleware] No session with id={session_id}")
                        return JsonResponse({'error': 'Invalid session', 'code': 'SESSION_NOT_FOUND'}, status=401)

            # Fallback to JTI mapping
            jti = token.get('jti')
            if not jti:
                return None
            # user_sessions.Session does not store access_token_jti; rely on session_id path only.

        except (TokenError, IndexError):
            # Invalid token format, let the auth middleware handle it
            pass
            
        return None
