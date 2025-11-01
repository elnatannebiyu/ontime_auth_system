from django.conf import settings
from django.contrib.auth.models import User
from django.contrib.auth.models import Group
from rest_framework.views import APIView
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework.response import Response
from rest_framework.throttling import AnonRateThrottle
from django_ratelimit.decorators import ratelimit
from django.utils.decorators import method_decorator
from django.views.decorators.csrf import csrf_exempt
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken, AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from accounts.jwt_auth import CustomTokenObtainPairSerializer, RefreshTokenRotation
from .models import UserSession
from .serializers import CookieTokenObtainPairSerializer, RegistrationSerializer, MeSerializer
from .permissions import (
    HasAnyRole,
    DjangoPermissionRequired,
    ReadOnlyOrPerm,
    IsTenantMember,
    TenantMatchesToken,
)

# Swagger imports guarded to avoid hard dependency in production where drf_yasg/pkg_resources may be unavailable
_ENABLE_SWAGGER = getattr(settings, 'ENABLE_SWAGGER', False) or settings.DEBUG
try:
    if _ENABLE_SWAGGER:
        from drf_yasg import openapi  # type: ignore
        from drf_yasg.utils import swagger_auto_schema  # type: ignore
    else:
        raise ImportError
except Exception:
    # Minimal shims: no-op decorator and simple openapi namespace with Parameter helper
    def swagger_auto_schema(*args, **kwargs):  # type: ignore
        def _decorator(func):
            return func
        return _decorator

    class _OpenApiShim:  # type: ignore
        IN_HEADER = 'header'
        TYPE_STRING = 'string'

        class Parameter:  # type: ignore
            def __init__(self, name, in_, description='', type=None, required=False, default=None):
                self.name = name
                self.in_ = in_
                self.description = description
                self.type = type
                self.required = required
                self.default = default

    openapi = _OpenApiShim()  # type: ignore

REFRESH_COOKIE_NAME = getattr(settings, "REFRESH_COOKIE_NAME", "refresh_token")
REFRESH_COOKIE_PATH = getattr(settings, "REFRESH_COOKIE_PATH", "/")


def set_refresh_cookie(response: Response, refresh: str):
    response.set_cookie(
        key=REFRESH_COOKIE_NAME,
        value=refresh,
        httponly=True,
        secure=not settings.DEBUG,
        samesite="Lax",
        path=REFRESH_COOKIE_PATH,
        max_age=60 * 60 * 24 * 7,
    )


def clear_refresh_cookie(response: Response):
    response.delete_cookie(REFRESH_COOKIE_NAME, path=REFRESH_COOKIE_PATH)


class LoginThrottle(AnonRateThrottle):
    rate = '5/minute'
    scope = 'login'

class RegisterThrottle(AnonRateThrottle):
    rate = '30/hour' if settings.DEBUG else '3/hour'
    scope = 'register'

@method_decorator(ratelimit(key='ip', rate='5/m', method='POST'), name='dispatch')
class TokenObtainPairWithCookieView(TokenObtainPairView):
    """Login endpoint that returns JWT tokens and sets refresh token in httpOnly cookie"""
    throttle_classes = [LoginThrottle]
    permission_classes = [AllowAny]
    serializer_class = CustomTokenObtainPairSerializer

    # Swagger header parameter for tenancy
    PARAM_TENANT = openapi.Parameter(
        name="X-Tenant-Id",
        in_=openapi.IN_HEADER,
        description="Tenant slug (e.g., ontime)",
        type=openapi.TYPE_STRING,
        required=True,
        default="ontime",
    )

    @swagger_auto_schema(
        manual_parameters=[PARAM_TENANT],
        operation_id="token_create",
        tags=["Auth"],
    )
    def post(self, request, *args, **kwargs):
        res = super().post(request, *args, **kwargs)
        if res.status_code == 200 and "refresh" in res.data:
            refresh = res.data.pop("refresh")
            set_refresh_cookie(res, refresh)
        return res

    def get_serializer_context(self):
        # Ensure serializer has access to request for tenant-aware claims
        return {"request": self.request, "view": self}


class CookieTokenRefreshView(TokenRefreshView):
    permission_classes = [AllowAny]
    # Disable DRF throttling here; refresh is cookie-based and often unauthenticated at DRF layer,
    # so global AnonRateThrottle could incorrectly rate-limit it.
    throttle_classes: list = []
    # Swagger header parameter for tenancy (required by middleware)
    PARAM_TENANT = openapi.Parameter(
        name="X-Tenant-Id",
        in_=openapi.IN_HEADER,
        description="Tenant slug (e.g., ontime)",
        type=openapi.TYPE_STRING,
        required=True,
        default="ontime",
    )

    @swagger_auto_schema(
        manual_parameters=[PARAM_TENANT],
        operation_id="token_refresh_create",
        tags=["Auth"],
    )
    def post(self, request, *args, **kwargs):
        # Get refresh token from cookie (same name used on login)
        refresh_token = request.COOKIES.get(REFRESH_COOKIE_NAME)
        
        if not refresh_token:
            return Response(
                {"detail": "Refresh token not found in cookies"},
                status=status.HTTP_401_UNAUTHORIZED
            )
        
        try:
            # Use token rotation
            rotator = RefreshTokenRotation()
            new_tokens = rotator.rotate_refresh_token(refresh_token, request)
            
            # Prepare response
            response = Response({
                'access': new_tokens['access'],
                'refresh': new_tokens['refresh']
            }, status=status.HTTP_200_OK)
            
            # Set new refresh token in cookie, consistent with login cookie config
            response.set_cookie(
                key=REFRESH_COOKIE_NAME,
                value=new_tokens['refresh'],
                httponly=True,
                secure=not settings.DEBUG,
                samesite='Lax',
                path=REFRESH_COOKIE_PATH,
                max_age=60 * 60 * 24 * 7,
            )
            
            return response
            
        except Exception as e:
            return Response(
                {"detail": str(e)},
                status=status.HTTP_401_UNAUTHORIZED
            )


class LogoutView(APIView):
    permission_classes = [IsAuthenticated]
    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="logout_create",
        tags=["Auth"],
    )
    def post(self, request):
        """Logout current session:
        - Revoke the current UserSession (is_active=False) using session_id claim in access token
          with a fallback to refresh cookie JTI
        - Clear the refresh token cookie
        """
        # Attempt to revoke by session_id from access token
        try:
            auth_header = request.META.get('HTTP_AUTHORIZATION', '')
            if auth_header.startswith('Bearer '):
                token_str = auth_header.split(' ')[1]
                at = AccessToken(token_str)
                sid = at.get('session_id')
                if sid:
                    try:
                        # Revoke without enforcing user equality; possession of the token implies control
                        session = UserSession.objects.get(id=sid)
                        session.revoke('user_logout')
                    except UserSession.DoesNotExist:
                        pass
                    # Revoke in new refresh-session backend as well
                    try:
                        from user_sessions.models import Session as RefreshSession
                        from django.utils import timezone as _tz
                        rs = RefreshSession.objects.get(id=sid)
                        rs.revoked_at = _tz.now()
                        rs.revoke_reason = 'user_logout'
                        rs.save()
                    except Exception:
                        pass
        except Exception:
            # Ignore token parsing errors and continue to cookie fallback
            pass

        # Fallback: try by refresh cookie JTI
        try:
            refresh_cookie = request.COOKIES.get(REFRESH_COOKIE_NAME)
            if refresh_cookie:
                rt = RefreshToken(refresh_cookie)
                sid = rt.get('session_id')
                jti = rt.get('jti')
                if sid:
                    try:
                        session = UserSession.objects.get(id=sid, user=request.user)
                        session.revoke('user_logout')
                    except UserSession.DoesNotExist:
                        pass
                        pass
                elif jti:
                    try:
                        session = UserSession.objects.get(refresh_token_jti=jti)
                        session.revoke('user_logout')
                    except UserSession.DoesNotExist:
                        pass
        except Exception:
            pass

        res = Response({"detail": "Logged out."}, status=status.HTTP_200_OK)
        clear_refresh_cookie(res)
        return res


class MeView(APIView):
    # Keep IsAuthenticated at the permission layer; perform tenant validations here to provide clearer messages
    permission_classes = [IsAuthenticated]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="me_retrieve",
        tags=["Auth"],
        responses={
            200: MeSerializer,
            400: "Unknown tenant. Provide X-Tenant-Id header (e.g., ontime).",
            401: "Authentication credentials were not provided.",
            403: "Token missing tenant_id, tenant mismatch, or not a member of this tenant.",
        },
    )
    def get(self, request):
        # 1) Tenant must be resolved by middleware (via header or host)
        tenant = getattr(request, "tenant", None)
        if tenant is None:
            return Response(
                {
                    "detail": "Unknown tenant.",
                    "hint": "Send header X-Tenant-Id: ontime when calling /api/* endpoints on localhost.",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # 2) Extract tenant_id from JWT claims (added during token creation)
        token_claims = {}
        # request.auth in SimpleJWT is a token object; try common access patterns safely
        try:
            if hasattr(request, "auth") and request.auth is not None:
                if hasattr(request.auth, "payload"):
                    token_claims = dict(getattr(request.auth, "payload") or {})
                elif isinstance(request.auth, dict):
                    token_claims = request.auth
        except Exception:  # noqa: BLE001
            token_claims = {}

        token_tenant = token_claims.get("tenant_id")
        if not token_tenant:
            return Response(
                {
                    "detail": "Token missing tenant context (tenant_id).",
                    "hint": "Obtain the token by calling POST /api/token/ WITH header X-Tenant-Id: ontime, then retry.",
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # 3) Token tenant must match resolved tenant
        if str(token_tenant) != str(getattr(tenant, "slug", tenant)):
            return Response(
                {
                    "detail": "Tenant mismatch between request and token.",
                    "expected": str(getattr(tenant, "slug", tenant)),
                    "got": str(token_tenant),
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # 4) Ensure user is a member of this tenant
        from .models import Membership

        is_member = Membership.objects.filter(user=request.user, tenant=tenant).exists()
        if not is_member:
            return Response(
                {
                    "detail": "Not a member of this tenant.",
                    "tenant": str(getattr(tenant, "slug", tenant)),
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # 5) Success
        return Response(MeSerializer(request.user, context={"request": request}).data)


# ---- Example protected views ----

class AdminOnlyView(APIView):
    """Accessible to users in the Administrator role (group)."""
    permission_classes = [HasAnyRole]
    # set required roles dynamically
    def get_permissions(self):
        p = super().get_permissions()[0]
        p.required_roles = ("Administrator",)
        return [p]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="admin_only_retrieve",
        tags=["Auth"],
    )
    def get(self, request):
        return Response({"ok": True, "msg": "Hello, Administrator!"})


class UserWriteView(APIView):
    """Read allowed to any authenticated user; write requires 'auth.change_user'."""
    permission_classes = [ReadOnlyOrPerm]
    def get_permissions(self):
        p = super().get_permissions()[0]
        p.required_perm = "auth.change_user"
        return [p]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="users_list",
        tags=["Auth"],
    )
    def get(self, request):
        users = list(User.objects.values("id", "username", "email")[:25])
        return Response({"results": users})

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="users_create",
        tags=["Auth"],
    )
    def post(self, request):
        # Example write that requires the perm
        return Response({"ok": True, "action": "Would write something"})


@method_decorator(csrf_exempt, name='dispatch')
@method_decorator(ratelimit(key='ip', rate=('30/h' if settings.DEBUG else '3/h'), method='POST'), name='dispatch')
class RegisterView(APIView):
    permission_classes = [AllowAny]
    throttle_classes = [RegisterThrottle]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="register_create",
        tags=["Auth"],
    )
    def post(self, request):
        tenant = getattr(request, "tenant", None)
        if tenant is None:
            return Response({"detail": "Unknown tenant."}, status=status.HTTP_400_BAD_REQUEST)

        ser = RegistrationSerializer(data=request.data)
        ser.is_valid(raise_exception=True)

        user = ser.create_user()

        # Create membership in this tenant
        from .models import Membership
        membership, _ = Membership.objects.get_or_create(user=user, tenant=tenant)

        # Ensure default role 'Viewer' exists and assign to new member
        viewer, created_viewer = Group.objects.get_or_create(name="Viewer")
        # Ensure Viewer has baseline read-only permissions (all 'view_*')
        try:
            from django.contrib.auth.models import Permission
            view_perms = Permission.objects.filter(codename__startswith='view_')
            # Add any missing view_* perms (idempotent)
            viewer.permissions.add(*view_perms)
        except Exception:
            # Do not block registration if permission assignment fails
            pass
        membership.roles.add(viewer)
        # Refresh user's permission cache so group perms are effective immediately
        try:
            if hasattr(user, "_perm_cache"):
                delattr(user, "_perm_cache")
        except Exception:
            pass

        # Build JWTs similar to CookieTokenObtainPairSerializer behavior
        token_ser = CookieTokenObtainPairSerializer()
        refresh = token_ser.get_token(user)
        access = refresh.access_token
        access["tenant_id"] = tenant.slug
        member_roles = list(membership.roles.values_list("name", flat=True))
        access["tenant_roles"] = member_roles
        # Add global roles and effective perms to access for client-side hints
        access["roles"] = list(user.groups.values_list("name", flat=True))
        try:
            access["perms"] = sorted(list(user.get_all_permissions()))
        except Exception:
            access["perms"] = []

        # ---- Create session entries (accounts.UserSession and user_sessions.Session) and embed session_id ----
        try:
            from .models import UserSession as LegacySession
            from user_sessions.models import Session as RefreshSession
            from django.utils import timezone as _tz
            import hashlib as _hashlib

            # Extract JTIs
            from rest_framework_simplejwt.tokens import RefreshToken as _RT
            rt = _RT(str(refresh))
            refresh_jti = rt.payload.get('jti', '')
            access_jti = access["jti"] if "jti" in access else rt.access_token["jti"]

            # Read device headers
            dev_id = request.META.get('HTTP_X_DEVICE_ID') or ''
            dev_name = request.META.get('HTTP_X_DEVICE_NAME') or request.META.get('HTTP_USER_AGENT', '')[:255]
            dev_type = request.META.get('HTTP_X_DEVICE_TYPE', 'mobile')
            os_name = request.META.get('HTTP_X_OS_NAME', '')
            os_version = request.META.get('HTTP_X_OS_VERSION', '')
            ip_addr = request.META.get('REMOTE_ADDR') or '127.0.0.1'
            ua = request.META.get('HTTP_USER_AGENT', '')

            # Create legacy session (authoritative session_id UUID)
            legacy = LegacySession.objects.create(
                user=user,
                device_id=dev_id or _hashlib.sha256(f"{ua}:{ip_addr}".encode()).hexdigest()[:32],
                device_name=dev_name,
                device_type=dev_type,
                os_name=os_name,
                os_version=os_version,
                ip_address=ip_addr,
                user_agent=ua,
                location='',
                refresh_token_jti=refresh_jti or _hashlib.sha256(str(refresh).encode()).hexdigest(),
                access_token_jti=access_jti or '',
                expires_at=_tz.now() + _tz.timedelta(days=7),
                is_active=True,
            )

            # Mirror into new refresh-session backend with same UUID
            refresh_hash = _hashlib.sha256(str(refresh).encode()).hexdigest()
            RefreshSession.objects.update_or_create(
                id=legacy.id,
                defaults={
                    'user': user,
                    'device': None,
                    'refresh_token_hash': refresh_hash,
                    'refresh_token_family': legacy.refresh_token_jti,
                    'rotation_counter': 0,
                    'ip_address': ip_addr,
                    'user_agent': ua,
                    'revoked_at': None,
                    'revoke_reason': '',
                    'expires_at': _tz.now() + _tz.timedelta(days=7),
                }
            )

            # Embed session_id into both tokens
            rt['session_id'] = str(legacy.id)
            access['session_id'] = str(legacy.id)
            refresh = rt  # assign back so cookie uses updated token
        except Exception:
            # Non-fatal: if session creation fails, proceed without blocking registration
            pass

        resp = Response({"access": str(access)}, status=status.HTTP_201_CREATED)
        set_refresh_cookie(resp, str(refresh))
        return resp
