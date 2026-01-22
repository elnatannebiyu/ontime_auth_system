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
    allow_create = bool(request.data.get('allow_create', False))
    
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
    
    # Find social account; create only if allowed
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
        # Check if user with email exists (case-insensitive)
        raw_email = info.get('email')
        email = (raw_email or '').strip().lower() or None
        user = None

        if email:
            user = User.objects.filter(email__iexact=email).first()

        # If user doesn't exist yet and creation is not allowed, prompt client to confirm
        if not user and not allow_create:
            return Response({'error': 'user_not_found'}, status=status.HTTP_404_NOT_FOUND)

        if not user:
            # Create new user (only when allowed and no existing email match)
            base_name = (email.split('@')[0] if email else f"{provider}_{info['provider_id']}")
            username = base_name
            counter = 1
            while User.objects.filter(username=username).exists():
                username = f"{base_name}{counter}"
                counter += 1

            # Ensure we never pass None for last_name (and first_name) because
            # the default Django auth_user.last_name column is NOT NULL.
            first_name = user_data.get('first_name') or info.get('given_name') or ''
            last_name = user_data.get('last_name') or info.get('family_name') or ''

            user = User.objects.create(
                username=username,
                email=email or '',
                first_name=first_name,
                last_name=last_name,
            )
            user.set_unusable_password()
            user.save()

        # Link or create social account for this user
        social_account = SocialAccount.objects.create(
            user=user,
            provider=provider,
            provider_id=info['provider_id'],
            email=email or '',
            name=info.get('name', ''),
            picture_url=info.get('picture', ''),
            extra_data=info,
        )
    
    # Check user status
    if not user.is_active:
        return Response({
            'error': 'Account is disabled'
        }, status=status.HTTP_403_FORBIDDEN)
    
    # Create or reuse a session bound to device
    # Resolve device from headers
    dev_id = request.META.get('HTTP_X_DEVICE_ID') or ''
    dev_name = request.META.get('HTTP_X_DEVICE_NAME') or request.META.get('HTTP_USER_AGENT', '')[:255]
    dev_type = request.META.get('HTTP_X_DEVICE_TYPE', 'mobile')
    from user_sessions.models import Device as RefreshDevice
    device_obj = None
    try:
        if dev_id:
            # Unique device_id across table; if owned by another user, fall back to unbound
            existing = RefreshDevice.objects.filter(device_id=dev_id).first()
            if existing and existing.user_id != user.id:
                device_obj = None
            else:
                device_obj, _ = RefreshDevice.objects.get_or_create(
                    device_id=dev_id,
                    defaults={
                        'user': user,
                        'device_name': dev_name or 'Unknown',
                        'device_type': dev_type or 'mobile',
                    }
                )
                # If exists for same user, update name/type best-effort
                if device_obj.user_id == user.id:
                    update = False
                    if dev_name and device_obj.device_name != dev_name:
                        device_obj.device_name = dev_name; update = True
                    if dev_type and device_obj.device_type != dev_type:
                        device_obj.device_type = dev_type; update = True
                    if update:
                        device_obj.save()
    except Exception:
        device_obj = None

    # Try to reuse a session for this user+device (even if previously revoked)
    from django.utils import timezone as _tz
    existing_session = None
    try:
        qs = Session.objects.filter(user=user)
        if device_obj:
            qs = qs.filter(device=device_obj)
        existing_session = qs.order_by('-last_used_at').first()
    except Exception:
        existing_session = None

    if existing_session:
        # Reactivate (if needed), extend expiry, rotate token, and keep the same session id
        try:
            if existing_session.revoked_at is not None:
                existing_session.revoked_at = None
                existing_session.revoke_reason = ''
                # extend expiry window from now
                existing_session.expires_at = _tz.now() + (_tz.timedelta(days=30))
                existing_session.save()
            refresh_token_plain = existing_session.rotate_token()
            session = existing_session
        except Exception:
            session, refresh_token_plain = Session.create_session(user=user, request=request, device=device_obj)

    # Enforce concurrent session limit (aligns with JWT login path)
    try:
        from django.conf import settings as _settings
        max_sessions = int(getattr(_settings, 'MAX_CONCURRENT_SESSIONS', 5))
    except Exception:
        max_sessions = 5
    if max_sessions > 0:
        try:
            # Enforce on new refresh-session backend (user_sessions.Session)
            active = Session.objects.filter(user=user, revoked_at__isnull=True).order_by('-last_used_at')
            if active.count() > max_sessions:
                for old in active[max_sessions:]:
                    old.revoked_at = _tz.now()
                    old.revoke_reason = 'session_limit_exceeded'
                    old.save(update_fields=['revoked_at', 'revoke_reason'])
        except Exception:
            pass
        try:
            # Also enforce on legacy accounts.UserSession for parity
            from .models import UserSession as LegacySession
            legacy_active = LegacySession.objects.filter(user=user, is_active=True).order_by('-last_activity')
            if legacy_active.count() > max_sessions:
                for old_l in legacy_active[max_sessions:]:
                    try:
                        old_l.revoke('session_limit_exceeded')
                    except Exception:
                        pass
        except Exception:
            pass
    else:
        session, refresh_token_plain = Session.create_session(user=user, request=request, device=device_obj)
    
    # Generate JWT tokens
    serializer = CustomTokenObtainPairSerializer()
    token = serializer.get_token(user)
    refresh = token
    access = refresh.access_token
    
    # Add session info to tokens (middleware expects 'session_id')
    refresh['session_id'] = str(session.id)
    access['session_id'] = str(session.id)

    # Ensure tenant membership and add tenant context expected by MeView (slug)
    tenant = getattr(request, 'tenant', None)
    if tenant:
        try:
            from .models import Membership
            from django.contrib.auth.models import Group
            membership, _ = Membership.objects.get_or_create(user=user, tenant=tenant)
            # Ensure default Viewer role exists and assign to member
            viewer, _created_viewer = Group.objects.get_or_create(name="Viewer")
            try:
                # Optionally hydrate Viewer with view_* perms, mirroring RegisterView best-effort behavior
                from django.contrib.auth.models import Permission
                view_perms = Permission.objects.filter(codename__startswith='view_')
                viewer.permissions.add(*view_perms)
            except Exception:
                # Non-fatal: permissions may not be fully available in some environments
                pass
            membership.roles.add(viewer)
            # Clear user's permission cache so group perms are effective immediately
            try:
                if hasattr(user, "_perm_cache"):
                    delattr(user, "_perm_cache")
            except Exception:
                pass
        except Exception:
            # Do not block login if membership/role assignment fails; MeView will enforce
            pass
        refresh['tenant_id'] = str(getattr(tenant, 'slug', tenant))
        access['tenant_id'] = str(getattr(tenant, 'slug', tenant))

    # Mirror into legacy accounts.UserSession for admin and compatibility
    try:
        from .models import UserSession as LegacySession
        from django.utils import timezone as _tz
        # Derive values required by legacy model
        # Extract JTIs from JWTs for rotation compatibility
        try:
            access_jti = access.get('jti')
        except Exception:
            access_jti = None
        try:
            refresh_jti = refresh.get('jti')
        except Exception:
            refresh_jti = None
        # Prefer explicit device headers sent by the app; fall back to UA/IP
        dev_id = request.META.get('HTTP_X_DEVICE_ID') or str(session.id)
        dev_name = request.META.get('HTTP_X_DEVICE_NAME') or request.META.get('HTTP_USER_AGENT', '')[:255]
        dev_type = request.META.get('HTTP_X_DEVICE_TYPE', 'mobile')
        os_name = request.META.get('HTTP_X_OS_NAME', '')
        os_version = request.META.get('HTTP_X_OS_VERSION', '')
        # Prefer original client IP from X-Forwarded-For, falling back to REMOTE_ADDR
        meta = getattr(request, 'META', {}) or {}
        xff = meta.get('HTTP_X_FORWARDED_FOR', '')
        if xff:
            # Take the first IP in the list (client IP)
            ip_addr = xff.split(',')[0].strip() or meta.get('REMOTE_ADDR') or '127.0.0.1'
        else:
            ip_addr = meta.get('REMOTE_ADDR') or '127.0.0.1'
        ua = request.META.get('HTTP_USER_AGENT', '')
        LegacySession.objects.update_or_create(
            id=session.id,
            defaults={
                'user': user,
                # Store the JWT refresh JTI so /api/token/refresh/ can validate against this session
                'refresh_token_jti': (refresh_jti or ''),
                'device_id': dev_id,
                'device_name': dev_name,
                'device_type': dev_type,
                'os_name': os_name,
                'os_version': os_version,
                'ip_address': ip_addr,
                'user_agent': ua,
                'location': '',
                'access_token_jti': (access_jti or ''),
                'expires_at': session.expires_at,
                'is_active': True,
                'revoked_at': None,
                'revoke_reason': '',
            }
        )
    except Exception:
        # Do not block login if legacy mirroring fails
        pass
    
    # Set refresh token cookie (must be the SimpleJWT refresh string so /api/token/refresh/ works)
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
    
    # Set HTTP-only cookie to the SimpleJWT refresh token so CookieTokenRefreshView can rotate it
    try:
        from accounts.views import REFRESH_COOKIE_NAME, REFRESH_COOKIE_PATH
    except Exception:
        REFRESH_COOKIE_NAME = 'refresh_token'
        REFRESH_COOKIE_PATH = '/'
    response.set_cookie(
        key=REFRESH_COOKIE_NAME,
        value=str(refresh),
        max_age=int(settings.SIMPLE_JWT['REFRESH_TOKEN_LIFETIME'].total_seconds()),
        httponly=True,
        secure=not settings.DEBUG,
        samesite='Lax',
        path=REFRESH_COOKIE_PATH,
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
