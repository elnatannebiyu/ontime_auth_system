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
from django.contrib.auth.password_validation import validate_password
from rest_framework_simplejwt.tokens import RefreshToken, AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from accounts.jwt_auth import CustomTokenObtainPairSerializer, RefreshTokenRotation
from .models import UserSession
from .serializers import CookieTokenObtainPairSerializer, RegistrationSerializer, MeSerializer, UserAdminSerializer
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
        # Enforce social-only policy when disabled
        try:
            allow = getattr(settings, 'AUTH_ALLOW_PASSWORD', True)
        except Exception:
            allow = True
        if not allow:
            return Response(
                {"detail": "Password-based login is disabled.", "error": "password_auth_disabled"},
                status=status.HTTP_403_FORBIDDEN,
            )
        # If django-ratelimit has flagged this request as limited, return a clear 429.
        # This protects against brute-force attempts at the view layer in addition to DRF throttling.
        try:
            if getattr(request, "limited", False):
                return Response(
                    {"detail": "Too many login attempts from this IP. Please wait a few minutes before trying again."},
                    status=status.HTTP_429_TOO_MANY_REQUESTS,
                )
        except Exception:
            # If anything goes wrong while checking ratelimit, fall through to normal handling.
            pass
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
        # Enforce social-only policy when disabled
        try:
            allow = getattr(settings, 'AUTH_ALLOW_PASSWORD', True)
        except Exception:
            allow = True
        if not allow:
            return Response(
                {"detail": "Registration via email/password is disabled.", "error": "registration_disabled"},
                status=status.HTTP_403_FORBIDDEN,
            )
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


class AdminUsersView(APIView):
    """Tenant-scoped Users admin: list and create members of current tenant.
    Requires AdminFrontend role or superuser.
    """
    permission_classes = [IsAuthenticated]

    def _require_admin(self, request):
        user = request.user
        try:
            return bool(getattr(user, 'is_superuser', False)) or user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            return bool(getattr(user, 'is_superuser', False))

    def get(self, request):
        if not self._require_admin(request):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        tenant = getattr(request, 'tenant', None)
        if tenant is None:
            return Response({'detail': 'Unknown tenant.'}, status=status.HTTP_400_BAD_REQUEST)
        from .models import Membership
        user_ids = Membership.objects.filter(tenant=tenant).values_list('user_id', flat=True)
        qs = User.objects.filter(id__in=user_ids)
        # Exclude staff accounts from the admin list
        qs = qs.filter(is_staff=False)
        # Exclude the requesting user (self) from the list
        qs = qs.exclude(pk=request.user.id)
        # Search
        search = (request.query_params.get('search') or '').strip()
        if search:
            from django.db.models import Q
            qs = qs.filter(
                Q(email__icontains=search) |
                Q(username__icontains=search) |
                Q(first_name__icontains=search) |
                Q(last_name__icontains=search)
            )
        # Ordering (comma-separated), whitelist fields
        ordering = (request.query_params.get('ordering') or '').strip()
        allowed = {
            'id', 'email', 'username', 'first_name', 'last_name', 'last_login', 'date_joined', 'is_active'
        }
        order_fields = []
        if ordering:
            for raw in ordering.split(','):
                f = raw.strip()
                if not f:
                    continue
                desc = f.startswith('-')
                name = f[1:] if desc else f
                if name in allowed:
                    order_fields.append(f)
        if order_fields:
            qs = qs.order_by(*order_fields)
        else:
            qs = qs.order_by('id')

        total = qs.count()
        # Pagination
        try:
            page = int(request.query_params.get('page') or 1)
        except Exception:
            page = 1
        try:
            page_size = int(request.query_params.get('page_size') or 20)
        except Exception:
            page_size = 20
        page_size = max(1, min(page_size, 100))
        start = (page - 1) * page_size
        end = start + page_size
        items = qs[start:end]
        data = UserAdminSerializer(items, many=True, context={"request": request}).data
        return Response({'results': data, 'count': total, 'page': page, 'page_size': page_size})

    def post(self, request):
        if not self._require_admin(request):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        tenant = getattr(request, 'tenant', None)
        if tenant is None:
            return Response({'detail': 'Unknown tenant.'}, status=status.HTTP_400_BAD_REQUEST)
        # Expected payload: { email, password, first_name?, last_name? }
        email = (request.data.get('email') or '').strip().lower()
        password = request.data.get('password') or ''
        first = request.data.get('first_name') or ''
        last = request.data.get('last_name') or ''
        if not email or not password:
            return Response({'detail': 'email and password are required'}, status=status.HTTP_400_BAD_REQUEST)
        # Reuse RegistrationSerializer validations
        ser = RegistrationSerializer(data={'email': email, 'password': password})
        ser.is_valid(raise_exception=True)
        user = ser.create_user()
        if first:
            user.first_name = first
        if last:
            user.last_name = last
        user.save()
        # Create tenant membership with Viewer role
        from .models import Membership
        membership, _ = Membership.objects.get_or_create(user=user, tenant=tenant)
        try:
            viewer, _ = Group.objects.get_or_create(name='Viewer')
            from django.contrib.auth.models import Permission
            view_perms = Permission.objects.filter(codename__startswith='view_')
            viewer.permissions.add(*view_perms)
            membership.roles.add(viewer)
        except Exception:
            pass
        return Response(UserAdminSerializer(user, context={"request": request}).data, status=status.HTTP_201_CREATED)


class AdminUserDetailView(APIView):
    """Retrieve/Update/Delete a tenant member. Protect self from update/delete."""
    permission_classes = [IsAuthenticated]

    def _require_admin(self, request):
        user = request.user
        try:
            return bool(getattr(user, 'is_superuser', False)) or user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            return bool(getattr(user, 'is_superuser', False))

    def _get_tenant_user(self, request, user_id):
        tenant = getattr(request, 'tenant', None)
        if tenant is None:
            return None, Response({'detail': 'Unknown tenant.'}, status=status.HTTP_400_BAD_REQUEST)
        from .models import Membership
        try:
            user = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None, Response({'detail': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
        is_member = Membership.objects.filter(user=user, tenant=tenant).exists()
        if not is_member:
            return None, Response({'detail': 'User not in this tenant'}, status=status.HTTP_404_NOT_FOUND)
        return user, None

    def get(self, request, user_id: int):
        if not self._require_admin(request):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        user, err = self._get_tenant_user(request, user_id)
        if err:
            return err
        return Response(UserAdminSerializer(user, context={"request": request}).data)

    def patch(self, request, user_id: int):
        if not self._require_admin(request):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        user, err = self._get_tenant_user(request, user_id)
        if err:
            return err
        if user.id == request.user.id:
            return Response({'detail': 'You cannot edit your own account via this endpoint.'}, status=status.HTTP_400_BAD_REQUEST)
        # Only allow updating basic profile and is_active
        allowed = {'email', 'first_name', 'last_name', 'is_active'}
        data = {k: v for k, v in request.data.items() if k in allowed}
        ser = UserAdminSerializer(user, data=data, partial=True, context={"request": request})
        ser.is_valid(raise_exception=True)
        ser.save()
        return Response(ser.data)

    def delete(self, request, user_id: int):
        if not self._require_admin(request):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        user, err = self._get_tenant_user(request, user_id)
        if err:
            return err
        if user.id == request.user.id:
            return Response({'detail': 'You cannot delete your own account.'}, status=status.HTTP_400_BAD_REQUEST)
        user.delete()
        return Response(status=status.HTTP_204_NO_CONTENT)


class AdminUserRolesView(APIView):
    """Add/Remove per-tenant roles for a user (Viewer/AdminFrontend)."""
    permission_classes = [IsAuthenticated]

    def _require_admin(self, request):
        user = request.user
        try:
            return bool(getattr(user, 'is_superuser', False)) or user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            return bool(getattr(user, 'is_superuser', False))

    def _get_member(self, request, user_id):
        tenant = getattr(request, 'tenant', None)
        if tenant is None:
            return None, None, Response({'detail': 'Unknown tenant.'}, status=status.HTTP_400_BAD_REQUEST)
        from .models import Membership
        try:
            u = User.objects.get(pk=user_id)
        except User.DoesNotExist:
            return None, None, Response({'detail': 'User not found'}, status=status.HTTP_404_NOT_FOUND)
        member = Membership.objects.filter(user=u, tenant=tenant).first()
        if not member:
            return None, None, Response({'detail': 'User not in this tenant'}, status=status.HTTP_404_NOT_FOUND)
        return u, member, None

    def post(self, request, user_id: int):
        if not self._require_admin(request):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        target, member, err = self._get_member(request, user_id)
        if err:
            return err
        role = (request.data.get('role') or '').strip()
        if role not in ('Viewer', 'AdminFrontend'):
            return Response({'detail': 'Invalid role'}, status=status.HTTP_400_BAD_REQUEST)
        g, _ = Group.objects.get_or_create(name=role)
        member.roles.add(g)
        return Response(UserAdminSerializer(target, context={"request": request}).data)

    def delete(self, request, user_id: int, role_name: str):
        if not self._require_admin(request):
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)
        if role_name not in ('Viewer', 'AdminFrontend'):
            return Response({'detail': 'Invalid role'}, status=status.HTTP_400_BAD_REQUEST)
        target, member, err = self._get_member(request, user_id)
        if err:
            return err
        try:
            g = Group.objects.get(name=role_name)
            member.roles.remove(g)
        except Group.DoesNotExist:
            pass
        return Response(UserAdminSerializer(target, context={"request": request}).data)


class ChangePasswordView(APIView):
    """Allow the authenticated user to change their password.
    Validates current password, enforces validators for new password,
    revokes all sessions, and clears the refresh cookie.
    """
    permission_classes = [IsAuthenticated]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="me_change_password",
        tags=["Auth"],
    )
    def post(self, request):
        tenant = getattr(request, "tenant", None)
        if tenant is None:
            return Response({"detail": "Unknown tenant."}, status=status.HTTP_400_BAD_REQUEST)

        current_password = request.data.get("current_password") or ""
        new_password = request.data.get("new_password") or ""

        if not current_password or not new_password:
            return Response({"detail": "current_password and new_password are required."}, status=status.HTTP_400_BAD_REQUEST)

        # Verify current password
        if not request.user.check_password(current_password):
            return Response({"detail": "Current password is incorrect."}, status=status.HTTP_400_BAD_REQUEST)

        # Validate new password strength
        try:
            validate_password(new_password, user=request.user)
        except Exception as e:
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        # Set new password
        request.user.set_password(new_password)
        request.user.save()

        # Revoke all sessions for this user in legacy UserSession table
        try:
            from .models import UserSession as LegacySession
            sessions = list(LegacySession.objects.filter(user=request.user, is_active=True))
            for s in sessions:
                try:
                    s.revoke('password_change')
                except Exception:
                    try:
                        s.is_active = False
                        s.save(update_fields=['is_active'])
                    except Exception:
                        pass
        except Exception:
            pass

        # Revoke all sessions in new user_sessions backend
        try:
            from user_sessions.models import Session as RefreshSession
            from django.utils import timezone as _tz
            RefreshSession.objects.filter(user=request.user, revoked_at__isnull=True).update(
                revoked_at=_tz.now(), revoke_reason='password_change'
            )
        except Exception:
            pass

        res = Response({"detail": "Password changed. You have been logged out from all devices."}, status=status.HTTP_200_OK)
        clear_refresh_cookie(res)
        return res
