from django.utils.deprecation import MiddlewareMixin
from rest_framework_simplejwt.tokens import AccessToken, RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from django.http import JsonResponse
from user_sessions.models import Session as RefreshSession
from .models import UserSession as LegacySession
from django.conf import settings
import logging

logger = logging.getLogger(__name__)


class SessionRevocationMiddleware(MiddlewareMixin):
    """Check if the session has been revoked on every authenticated request"""
    
    def process_request(self, request):
        # Skip for non-API routes
        if not request.path.startswith('/api/'):
            return None


class AuthenticatedCSRFMiddleware(MiddlewareMixin):
    """Enforce double-submit CSRF for authenticated unsafe API methods."""
    def process_request(self, request):
        # Only protect API routes
        if not request.path.startswith('/api/'):
            return None
        # Safe methods do not require CSRF
        if request.method in ('GET', 'HEAD', 'OPTIONS'):
            return None
        # Skip public/auth endpoints
        _skip_paths = {
            '/api/social/login/',
            '/api/token/',
            '/api/token/refresh/',
            '/api/register/',
            '/api/password-reset/request/',
            '/api/password-reset/verify/',
            '/api/password-reset/confirm/',
        }
        if request.path in _skip_paths:
            return None
        # Apply only when using Bearer tokens (authenticated API clients)
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        if not auth_header.startswith('Bearer '):
            return None
        # Double-submit: header must match cookie
        csrf_cookie = request.COOKIES.get('csrftoken') or ''
        csrf_header = request.META.get('HTTP_X_CSRFTOKEN') or request.META.get('HTTP_X_CSRF_TOKEN') or ''
        if not csrf_cookie or csrf_cookie != csrf_header:
            return JsonResponse({'error': 'CSRF failed'}, status=403)
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
            
            # Enforce binding between access token and refresh-cookie session (if cookie present)
            try:
                refresh_cookie_name = getattr(settings, 'REFRESH_COOKIE_NAME', 'refresh_token')
                refresh_cookie_value = request.COOKIES.get(refresh_cookie_name)
                if refresh_cookie_value:
                    rt = RefreshToken(refresh_cookie_value)
                    refresh_sid = rt.get('session_id')
                    if refresh_sid and str(refresh_sid) != str(session_id):
                        logger.warning(
                            f"[TokenSessionBinding] Access/refresh session mismatch: access.session_id={session_id} refresh.session_id={refresh_sid}"
                        )
                        return JsonResponse({
                            'error': 'Session cookie mismatch',
                            'code': 'SESSION_COOKIE_MISMATCH'
                        }, status=401)
            except Exception:
                # If cookie is absent or cannot be parsed, continue with existing checks
                pass
            
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
