"""Custom JWT authentication with token versioning and refresh token rotation"""
import hashlib
import secrets
from datetime import datetime, timedelta
from typing import Optional, Tuple

from django.contrib.auth import get_user_model
from django.utils import timezone
from rest_framework_simplejwt.authentication import JWTAuthentication
from rest_framework_simplejwt.exceptions import InvalidToken, TokenError
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.serializers import TokenObtainPairSerializer
from rest_framework.exceptions import AuthenticationFailed

from accounts.models import UserSession
from accounts.models import Membership
from tenants.models import Tenant
from user_sessions.models import Session as RefreshSession

User = get_user_model()


def _get_client_ip(request) -> str:
    """Return best-effort client IP, preferring X-Forwarded-For over REMOTE_ADDR.

    Falls back to 127.0.0.1 when nothing is available, so existing behavior is
    preserved for local/dev setups.
    """
    try:
        xff = request.META.get("HTTP_X_FORWARDED_FOR")
        if xff:
            # X-Forwarded-For may contain multiple IPs, client is first
            return xff.split(",")[0].strip() or "127.0.0.1"
    except Exception:
        pass
    return request.META.get("REMOTE_ADDR", "") or "127.0.0.1"


def _infer_os_from_ua(ua: str) -> Tuple[str, str]:
    """Very small heuristic to infer OS name/version from User-Agent.

    This is only used when explicit X-OS-Name / X-OS-Version headers are not
    provided by the client. It is intentionally simple and best-effort.
    """
    if not ua:
        return "Unknown", ""
    ua_low = ua.lower()

    # Android
    if "android" in ua_low:
        name = "Android"
        # e.g. "Android 14" or "Android 15" in UA
        try:
            idx = ua_low.index("android")
            rest = ua[idx + len("android"):].strip()
            # First token after "Android" is usually the version
            version = rest.split(";", 1)[0].split(" ", 1)[0].strip()
        except Exception:
            version = ""
        return name, version

    # iOS (iPhone / iPad)
    if "iphone" in ua_low or "ipad" in ua_low:
        name = "iOS"
        # Versions often appear as "OS 16_5" etc.
        version = ""
        try:
            if " os " in ua_low:
                part = ua_low.split(" os ", 1)[1]
                token = part.split(" ", 1)[0]
                version = token.replace("_", ".")
        except Exception:
            version = ""
        return name, version

    # macOS
    if "mac os x" in ua_low or "macintosh" in ua_low:
        name = "macOS"
        version = ""
        try:
            if "mac os x" in ua_low:
                part = ua_low.split("mac os x", 1)[1]
                token = part.split(")", 1)[0].strip()
                # token like "10_15_7" -> "10.15.7"
                version = token.replace("_", ".").strip()
        except Exception:
            version = ""
        return name, version

    # Windows
    if "windows nt" in ua_low:
        name = "Windows"
        version = ""
        try:
            part = ua_low.split("windows nt", 1)[1]
            token = part.split(";", 1)[0].strip()
            version = token
        except Exception:
            version = ""
        return name, version

    # Fallback for other platforms
    return "Unknown", ""


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
        # First, validate credentials. If invalid, provide a more specific error
        # when the account exists but has no usable password (i.e., social-only),
        # and otherwise normalize the message so clients always see a generic
        # "invalid username and password" string instead of SimpleJWT defaults.
        try:
            data = super().validate(attrs)
        except AuthenticationFailed as exc:
            username = attrs.get('username') or ''
            # Look up user case-insensitively by username or email
            user = (User.objects.filter(username__iexact=username).first()
                    or User.objects.filter(email__iexact=username).first())
            if user is not None and not user.has_usable_password():
                # Distinct signal for social-only accounts - use dict for structured error
                from rest_framework.exceptions import ValidationError
                raise ValidationError({
                    'detail': 'This account uses social login only.',
                    'error': 'password_auth_not_set',
                    'hint': 'Use Google sign-in or enable password in app settings.'
                })
            # For all other credential failures, return a consistent generic message
            raise AuthenticationFailed('invalid username and password') from exc
        
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
        
        # Create or update session (device-based reuse, aligned with social login)
        request = self.context.get('request')
        if request:
            # Get tenant_id from request
            tenant_id = request.META.get('HTTP_X_TENANT_ID', 'ontime')

            # Enforce membership: user must belong to requested tenant
            try:
                tenant = Tenant.objects.get(slug=tenant_id)
            except Tenant.DoesNotExist:
                raise AuthenticationFailed('unknown_tenant')

            if not Membership.objects.filter(user=self.user, tenant=tenant).exists():
                # Deny login if user is not a member of this tenant
                raise AuthenticationFailed('not_member_of_tenant')

            # Determine roles server-side after login; do not rely on client headers
            
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
            
            # Get access token JTI
            access_token_jti = refresh_token.access_token.payload.get('jti', '')
            
            # Derive OS info and client IP when headers are missing
            ua = request.META.get('HTTP_USER_AGENT', '')[:500]
            os_name = request.META.get('HTTP_X_OS_NAME', '')
            os_version = request.META.get('HTTP_X_OS_VERSION', '')
            if not os_name:
                inferred_name, inferred_ver = _infer_os_from_ua(ua)
                os_name = inferred_name
                if not os_version:
                    os_version = inferred_ver
            client_ip = _get_client_ip(request)

            # Normalize device type to one of: 'mobile' or 'web'
            dev_type_raw = (request.META.get('HTTP_X_DEVICE_TYPE', '') or '').lower().strip()
            device_type_norm = 'mobile' if dev_type_raw == 'mobile' else 'web'

            # Try to find existing session for this device and update it, or create new
            # Handle edge case where multiple sessions exist for same device_id
            try:
                session, created = UserSession.objects.update_or_create(
                    user=self.user,
                    device_id=device_id,
                    defaults={
                        'device_name': request.META.get('HTTP_X_DEVICE_NAME', ''),
                        'device_type': device_type_norm,
                        'os_name': os_name,
                        'os_version': os_version,
                        'ip_address': client_ip,
                        'user_agent': ua,
                        'refresh_token_jti': jti,
                        'access_token_jti': access_token_jti,
                        'expires_at': timezone.now() + timedelta(days=7),
                        'is_active': True,
                        'last_activity': timezone.now()
                    }
                )
            except UserSession.MultipleObjectsReturned:
                # Multiple sessions exist for this device - use most recent and delete others
                sessions = UserSession.objects.filter(user=self.user, device_id=device_id).order_by('-last_activity')
                session = sessions.first()
                # Update the most recent session
                session.device_name = request.META.get('HTTP_X_DEVICE_NAME', '')
                session.device_type = device_type_norm
                session.os_name = os_name
                session.os_version = os_version
                session.ip_address = client_ip
                session.user_agent = ua
                session.refresh_token_jti = jti
                session.access_token_jti = access_token_jti
                session.expires_at = timezone.now() + timedelta(days=7)
                session.is_active = True
                session.last_activity = timezone.now()
                session.save()
                # Delete duplicates
                sessions.exclude(id=session.id).delete()
                created = False
            
            # Enforce per-device-type session concurrency limits
            from django.conf import settings
            # Prefer per-type limits if provided; fallback to global
            global_limit = getattr(settings, 'MAX_CONCURRENT_SESSIONS', 5)
            mobile_limit = getattr(settings, 'MOBILE_MAX_CONCURRENT_SESSIONS', None)
            web_limit = getattr(settings, 'WEB_MAX_CONCURRENT_SESSIONS', None)

            if device_type_norm == 'mobile':
                limit = int(mobile_limit) if mobile_limit is not None else int(global_limit)
                type_filter = {'device_type': 'mobile'}
            else:
                limit = int(web_limit) if web_limit is not None else int(global_limit)
                type_filter = {'device_type': 'web'}

            if limit > 0:
                active_sessions = UserSession.objects.filter(
                    user=self.user,
                    is_active=True,
                    **type_filter,
                ).order_by('-last_activity')

                if active_sessions.count() > limit:
                    sessions_to_revoke = active_sessions[limit:]
                    for old_session in sessions_to_revoke:
                        old_session.revoke('session_limit_exceeded')
                        # Also revoke in new backend
                        try:
                            rs = RefreshSession.objects.get(id=old_session.id)
                            rs.revoked_at = timezone.now()
                            rs.revoke_reason = 'session_limit_exceeded'
                            rs.save()
                        except RefreshSession.DoesNotExist:
                            pass
            
            # Store session ID in token
            refresh_token['session_id'] = str(session.id)
            # Also embed session_id into the access token for middleware checks
            refresh_token.access_token['session_id'] = str(session.id)
            data['refresh'] = str(refresh_token)
            data['access'] = str(refresh_token.access_token)

            # Mirror into new refresh session backend so Admin and middleware can use either
            try:
                # Use same UUID so tokens and both tables align
                import hashlib as _hashlib
                from django.utils import timezone as _tz
                # Hash the actual SimpleJWT refresh string for audit
                refresh_hash = _hashlib.sha256(str(refresh_token).encode()).hexdigest()
                RefreshSession.objects.update_or_create(
                    id=session.id,
                    defaults={
                        'user': self.user,
                        'device': None,
                        'refresh_token_hash': refresh_hash,
                        'refresh_token_family': session.refresh_token_jti if hasattr(session, 'refresh_token_jti') else jti or '',
                        'rotation_counter': 0,
                        'ip_address': client_ip,
                        'user_agent': ua,
                        'revoked_at': None,
                        'revoke_reason': '',
                        # Keep a reasonable expiry for audit; SimpleJWT refresh lifetime is 7 days in settings
                        'expires_at': _tz.now() + timedelta(days=7),
                    }
                )
            except Exception:
                # Do not block login if mirroring fails
                pass
        
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
                    
                    # Ensure access token also carries session_id
                    new_token.access_token['session_id'] = str(session.id)
                    
                    # Update session with new JTIs
                    session.refresh_token_jti = new_token['jti']
                    session.access_token_jti = new_token.access_token['jti']
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
