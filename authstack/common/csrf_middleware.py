"""
AUDIT FIX #5 & #6: Enhanced CSRF Protection Middleware

This middleware ensures CSRF tokens are unique per session and properly validated
on all state-changing endpoints (POST, PUT, PATCH, DELETE).
"""
from django.middleware.csrf import CsrfViewMiddleware
import logging
from django.utils.crypto import get_random_string


class SessionBoundCSRFMiddleware(CsrfViewMiddleware):
    """
    Enhanced CSRF middleware that binds CSRF tokens to user sessions.
    
    This fixes audit findings #5 (Missing CSRF Protection) and #6 (CSRF token reuse).
    Each user session gets a unique CSRF token that cannot be reused across accounts.
    """
    
    def process_view(self, request, callback, callback_args, callback_kwargs):
        """
        Override to bind CSRF token to authenticated user session.
        """
        # For authenticated requests, ensure CSRF token is bound to user
        if hasattr(request, 'user') and request.user.is_authenticated:
            # Get or create session-specific CSRF token
            session_key = f'csrf_token_{request.user.id}'
            
            # If user doesn't have a session-bound CSRF token, generate one
            if not request.session.get(session_key):
                request.session[session_key] = get_random_string(32)
            
            # Override the CSRF token with the session-bound one
            request.META['CSRF_COOKIE'] = request.session[session_key]
        
        # Call parent implementation for standard CSRF validation
        return super().process_view(request, callback, callback_args, callback_kwargs)
    
    def _reject(self, request, reason):
        logger = logging.getLogger(__name__)
        try:
            user_id = getattr(getattr(request, 'user', None), 'id', None)
            referer = request.META.get('HTTP_REFERER', '')
            origin = request.META.get('HTTP_ORIGIN', '')
            host = request.META.get('HTTP_HOST', '')
            x_csrf = 'HTTP_X_CSRFTOKEN' in request.META
            cookie_csrf = 'csrftoken' in getattr(request, 'COOKIES', {})
            ip = (request.META.get('HTTP_X_FORWARDED_FOR') or '').split(',')[0].strip() or request.META.get('REMOTE_ADDR', '')
            ua = request.META.get('HTTP_USER_AGENT', '')
            logger.warning(
                "CSRF reject: reason=%s path=%s method=%s user_id=%s referer=%s origin=%s host=%s has_x_csrf=%s has_cookie_csrf=%s ip=%s ua=%s",
                str(reason), getattr(request, 'path', ''), getattr(request, 'method', ''), str(user_id), referer, origin, host, x_csrf, cookie_csrf, ip, ua[:120]
            )
        except Exception:
            pass
        return super()._reject(request, reason)
    
    def process_response(self, request, response):
        """
        Ensure CSRF cookie is set with session-bound token for authenticated users.
        """
        if hasattr(request, 'user') and request.user.is_authenticated:
            session_key = f'csrf_token_{request.user.id}'
            csrf_token = request.session.get(session_key)
            if csrf_token:
                # Set the CSRF cookie with the session-bound token
                response.set_cookie(
                    'csrftoken',
                    csrf_token,
                    max_age=31449600,  # 1 year
                    secure=not request.META.get('DEBUG', False),
                    httponly=False,  # Must be readable by JavaScript
                    samesite='Lax',
                )
        
        return super().process_response(request, response)
