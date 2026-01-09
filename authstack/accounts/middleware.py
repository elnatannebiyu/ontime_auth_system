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


class TokenSessionBindingMiddleware(MiddlewareMixin):
    """AUDIT FIX #6 & #7: Enforce server-side token-to-session binding.
    
    Prevents token injection attacks by validating that:
    1. Access tokens can only be used by the user who owns the session
    2. Tokens cannot be arbitrarily swapped in client-side storage
    3. Session ownership is verified server-side on every request
    
    This fixes:
    - Risk #6: Improper Authentication State Management via Client-Side Tokens
    - Risk #7: Broken Authentication – Frontend–Backend Login Flow Inconsistency
    """
    
    def process_request(self, request):
        # Skip for non-API routes and public endpoints
        if not request.path.startswith('/api/'):
            return None
        
        _skip_paths = {
            '/api/token/',
            '/api/token/refresh/',
            '/api/register/',
            '/api/social/login/',
            '/api/password-reset/request/',
            '/api/password-reset/confirm/',
        }
        if request.path in _skip_paths:
            return None
        
        # Get authorization header
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        if not auth_header.startswith('Bearer '):
            return None
        
        try:
            # Extract and decode access token
            token_str = auth_header.split(' ')[1]
            token = AccessToken(token_str)
            
            # Get user_id and session_id from token claims
            token_user_id = token.get('user_id')
            session_id = token.get('session_id')
            
            if not token_user_id or not session_id:
                # Token missing required claims - let auth middleware handle
                return None
            
            # Verify session exists and belongs to the token's user
            try:
                session = RefreshSession.objects.get(id=session_id)
                
                # CRITICAL: Verify session owner matches token user
                if str(session.user_id) != str(token_user_id):
                    logger.warning(
                        f'[TokenSessionBinding] Token injection detected: '
                        f'token_user={token_user_id} session_owner={session.user_id} '
                        f'session_id={session_id} ip={request.META.get("REMOTE_ADDR")}'
                    )
                    return JsonResponse({
                        'error': 'Token-session mismatch detected',
                        'code': 'TOKEN_INJECTION_DETECTED'
                    }, status=401)
                
                # Verify session is not revoked
                if session.revoked_at:
                    return JsonResponse({
                        'error': 'Session has been revoked',
                        'code': 'SESSION_REVOKED'
                    }, status=401)
                
            except RefreshSession.DoesNotExist:
                # Try legacy session table
                try:
                    legacy_session = LegacySession.objects.get(id=session_id)
                    
                    if str(legacy_session.user_id) != str(token_user_id):
                        logger.warning(
                            f'[TokenSessionBinding] Token injection (legacy): '
                            f'token_user={token_user_id} session_owner={legacy_session.user_id}'
                        )
                        return JsonResponse({
                            'error': 'Token-session mismatch detected',
                            'code': 'TOKEN_INJECTION_DETECTED'
                        }, status=401)
                    
                    if not legacy_session.is_active:
                        return JsonResponse({
                            'error': 'Session has been revoked',
                            'code': 'SESSION_REVOKED'
                        }, status=401)
                        
                except LegacySession.DoesNotExist:
                    logger.warning(
                        f'[TokenSessionBinding] Session not found: session_id={session_id}'
                    )
                    return JsonResponse({
                        'error': 'Invalid session',
                        'code': 'SESSION_NOT_FOUND'
                    }, status=401)
        
        except (TokenError, IndexError, ValueError) as e:
            # Invalid token - let auth middleware handle
            pass
        
        return None
