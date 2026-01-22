from django.conf import settings
import secrets
from django.contrib.auth.models import User
from django.contrib.auth.models import Group
from django.core.mail import send_mail
from django.urls import reverse
from django.utils import timezone
from django.shortcuts import render
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
from accounts.jwt_auth import CustomTokenObtainPairSerializer, RefreshTokenRotation, _get_client_ip, _infer_os_from_ua
from .models import UserSession, ActionToken, UserProfile
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

@method_decorator(ratelimit(key='ip', rate='5/m', method='POST', block=False), name='dispatch')
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
            # Set CSRF double-submit cookie so authenticated writes can include X-CSRFToken
            try:
                csrf = secrets.token_urlsafe(32)
            except Exception:
                csrf = "csrf"
            res.set_cookie(
                key='csrftoken',
                value=csrf,
                httponly=False,
                secure=not settings.DEBUG,
                samesite='Lax',
                max_age=60*60*24*7,
            )
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
            # Also rotate/set CSRF cookie for double-submit on authenticated writes
            try:
                csrf = secrets.token_urlsafe(32)
            except Exception:
                csrf = "csrf"
            response.set_cookie(
                key='csrftoken',
                value=csrf,
                httponly=False,
                secure=not settings.DEBUG,
                samesite='Lax',
                max_age=60*60*24*7,
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

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="me_update",
        tags=["Auth"],
    )
    def put(self, request):
        """Update basic profile fields (currently first_name, last_name) for the
        authenticated user. Reuses the same tenant and membership checks as
        the GET handler to ensure the user is operating within the resolved
        tenant.
        """

        tenant = getattr(request, "tenant", None)
        if tenant is None:
            return Response(
                {
                    "detail": "Unknown tenant.",
                    "hint": "Send header X-Tenant-Id: ontime when calling /api/* endpoints on localhost.",
                },
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Ensure token tenant matches resolved tenant, mirroring GET logic
        token_claims = {}
        try:
            if hasattr(request, "auth") and request.auth is not None:
                if hasattr(request.auth, "payload"):
                    token_claims = dict(getattr(request.auth, "payload") or {})
                elif isinstance(request.auth, dict):
                    token_claims = request.auth
        except Exception:
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

        if str(token_tenant) != str(getattr(tenant, "slug", tenant)):
            return Response(
                {
                    "detail": "Tenant mismatch between request and token.",
                    "expected": str(getattr(tenant, "slug", tenant)),
                    "got": str(token_tenant),
                },
                status=status.HTTP_403_FORBIDDEN,
            )

        # Ensure user is a member of this tenant
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

        # Apply basic profile updates; ignore other fields for now.
        first_name = (request.data.get("first_name") or "").strip()
        last_name = (request.data.get("last_name") or "").strip()

        user = request.user
        if first_name is not None:
            user.first_name = first_name
        if last_name is not None:
            user.last_name = last_name
        user.save(update_fields=["first_name", "last_name"])

        return Response(MeSerializer(user, context={"request": request}).data)


@method_decorator(ratelimit(key='user', rate='3/h', method='POST', block=False), name='dispatch')
class RequestEmailVerificationView(APIView):
    """Send a verification email with a one-time token to the current user."""

    permission_classes = [IsAuthenticated]

    def post(self, request):
        # Avoid abuse: limit each authenticated user to 3 verification emails
        # per hour. When the limit is exceeded, django_ratelimit marks the
        # request as limited and we return a clear 429 response with
        # client-friendly metadata.
        try:
            if getattr(request, "limited", False):
                # We don't get the exact reset time from django-ratelimit, so
                # conservatively instruct the client to wait up to 1 hour.
                retry_after_seconds = 60 * 60
                next_allowed_at = (timezone.now() + timezone.timedelta(seconds=retry_after_seconds)).isoformat()
                return Response(
                    {
                        "detail": "Too many verification attempts. Please wait before trying again.",
                        "error": "too_many_requests",
                        "retry_after_seconds": retry_after_seconds,
                        "next_allowed_at": next_allowed_at,
                    },
                    status=status.HTTP_429_TOO_MANY_REQUESTS,
                )
        except Exception:
            # If ratelimit integration fails for any reason, fall back to
            # normal behavior rather than breaking the endpoint.
            pass

        user = request.user
        email = (user.email or "").strip()
        if not email:
            return Response(
                {"detail": "No email address on file for this account."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Ensure profile exists
        profile, _ = UserProfile.objects.get_or_create(user=user)
        if profile.email_verified:
            return Response(
                {"detail": "Email already verified."},
                status=status.HTTP_200_OK,
            )

        # Enforce a per-account cooldown between verification email sends,
        # independent of the global rate limiter. This ensures that a single
        # account cannot request a new verification email more frequently than
        # EMAIL_VERIFICATION_COOLDOWN_SECONDS, even if the client is restarted
        # or caches are cleared.
        cooldown_seconds = int(
            getattr(settings, "EMAIL_VERIFICATION_COOLDOWN_SECONDS", 3600)
        )
        if cooldown_seconds > 0:
            from django.db.models import Max

            latest_token = (
                ActionToken.objects.filter(
                    user=user,
                    purpose=ActionToken.PURPOSE_VERIFY_EMAIL,
                )
                .aggregate(last_created=Max("created_at"))
                .get("last_created")
            )
            if latest_token is not None:
                now = timezone.now()
                elapsed = (now - latest_token).total_seconds()
                if elapsed < cooldown_seconds:
                    retry_after_seconds = int(cooldown_seconds - elapsed)
                    next_allowed_at = (
                        now + timezone.timedelta(seconds=retry_after_seconds)
                    ).isoformat()
                    return Response(
                        {
                            "detail": "A verification email was recently sent. Please wait before requesting another.",
                            "error": "cooldown_active",
                            "retry_after_seconds": retry_after_seconds,
                            "next_allowed_at": next_allowed_at,
                        },
                        status=status.HTTP_429_TOO_MANY_REQUESTS,
                    )

        # Create a one-time token valid for 1 hour
        import secrets

        token_str = secrets.token_urlsafe(48)
        now = timezone.now()
        expires_at = now + timezone.timedelta(hours=1)
        ActionToken.objects.create(
            user=user,
            purpose=ActionToken.PURPOSE_VERIFY_EMAIL,
            token=token_str,
            expires_at=expires_at,
        )

        # Build verification URL relative to this request
        verify_path = reverse("verify_email")
        verify_url = request.build_absolute_uri(f"{verify_path}?token={token_str}")

        subject = "Verify your Ontime account"
        message = (
            "Hello,\n\n"
            "Please confirm your email address for your Ontime account by clicking the link "
            "below:\n\n"
            f"{verify_url}\n\n"
            "If you did not request this, you can ignore this email. The link will expire in 1 hour."
        )

        try:
            send_mail(
                subject,
                message,
                settings.DEFAULT_FROM_EMAIL,
                [email],
                fail_silently=False,
            )
        except Exception as exc:
            # Surface a clear API error instead of an unhandled 500 while still
            # logging the underlying SMTP issue on the server.
            return Response(
                {
                    "detail": "Could not send verification email.",
                    "error": "email_send_failed",
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {"detail": "Verification email sent."},
            status=status.HTTP_200_OK,
        )


class VerifyEmailView(APIView):
    """Verify a user's email based on a one-time token."""

    permission_classes = [AllowAny]

    def get(self, request):
        token_str = (request.query_params.get("token") or "").strip()
        if not token_str:
            # Missing token: render a friendly error page for browsers and
            # JSON for API clients.
            accept = (request.META.get("HTTP_ACCEPT") or "").lower()
            if "text/html" in accept or "*/*" in accept or not accept:
                return render(
                    request,
                    "verify_email_error.html",
                    {
                        "app_name": "Ontime Ethiopia",
                        "support_email": "support@aitechnologiesplc.com",
                    },
                )
            return Response(
                {"detail": "Missing token."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        now = timezone.now()
        try:
            t = ActionToken.objects.select_related("user").get(
                token=token_str,
                purpose=ActionToken.PURPOSE_VERIFY_EMAIL,
                used=False,
                expires_at__gt=now,
            )
        except ActionToken.DoesNotExist:
            accept = (request.META.get("HTTP_ACCEPT") or "").lower()
            if "text/html" in accept or "*/*" in accept or not accept:
                return render(
                    request,
                    "verify_email_error.html",
                    {
                        "app_name": "Ontime",
                        "support_email": "support@aitechnologiesplc.com",
                    },
                )
            return Response(
                {"detail": "Invalid or expired token."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Mark token used and flag email as verified
        t.used = True
        t.save(update_fields=["used"])

        profile, _ = UserProfile.objects.get_or_create(user=t.user)
        if not profile.email_verified:
            profile.email_verified = True
            profile.save(update_fields=["email_verified"])

        # For normal browsers, render a friendly HTML page instead of raw JSON.
        accept = (request.META.get("HTTP_ACCEPT") or "").lower()
        if "text/html" in accept or "*/*" in accept or not accept:
            return render(
                request,
                "verify_email_success.html",
                {
                    "app_name": "Ontime Ethiopia",
                },
            )

        # Fallback: JSON response for API clients
        return Response(
            {"detail": "Email verified successfully."},
            status=status.HTTP_200_OK,
        )


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
    """AUDIT FIX: Enforce proper RBAC on /api/users/ endpoint.
    
    GET requires 'auth.view_user' permission (not just authentication).
    POST/PUT/DELETE require 'auth.change_user' permission.
    This fixes the broken access control vulnerability where frontend restrictions
    were bypassed via direct API calls.
    """
    permission_classes = [DjangoPermissionRequired]
    
    def get_permissions(self):
        p = super().get_permissions()[0]
        # Require view permission for GET, change permission for writes
        if self.request.method in ('GET', 'HEAD', 'OPTIONS'):
            p.required_perm = "auth.view_user"
        else:
            p.required_perm = "auth.change_user"
        return [p]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="users_list",
        tags=["Auth"],
    )
    def get(self, request):
        # Permission check is enforced by DjangoPermissionRequired above
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


# AUDIT FIX #5: Removed csrf_exempt to enable CSRF protection on registration
@method_decorator(ratelimit(key='ip', rate=('30/h' if settings.DEBUG else '3/h'), method='POST', block=False), name='dispatch')
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

        # AUDIT FIX #8: Ensure default role 'Viewer' exists with restricted permissions
        viewer, created_viewer = Group.objects.get_or_create(name="Viewer")
        # LOW RISK FIX: Only grant safe, non-sensitive view permissions to Viewer role
        # Exclude sensitive models: auth.User, admin.LogEntry, sessions.Session, etc.
        try:
            from django.contrib.auth.models import Permission
            from django.contrib.contenttypes.models import ContentType
            
            # Define safe apps/models that Viewers can access
            safe_apps = ['onchannels', 'series', 'live']  # App-specific content only
            
            # Get content types for safe apps only
            safe_content_types = ContentType.objects.filter(app_label__in=safe_apps)
            
            # Get view permissions for safe models only
            safe_view_perms = Permission.objects.filter(
                content_type__in=safe_content_types,
                codename__startswith='view_'
            )
            
            # Clear existing permissions and set only safe ones
            if created_viewer:
                viewer.permissions.set(safe_view_perms)
            else:
                # For existing Viewer role, only add safe perms (don't remove existing)
                viewer.permissions.add(*safe_view_perms)
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

            # Read device headers and infer OS/IP where headers are missing
            dev_id = request.META.get('HTTP_X_DEVICE_ID') or ''
            ua = request.META.get('HTTP_USER_AGENT', '')
            dev_name = request.META.get('HTTP_X_DEVICE_NAME') or ua[:255]
            dev_type = request.META.get('HTTP_X_DEVICE_TYPE', 'mobile')
            os_name = request.META.get('HTTP_X_OS_NAME', '')
            os_version = request.META.get('HTTP_X_OS_VERSION', '')
            if not os_name:
                inferred_name, inferred_ver = _infer_os_from_ua(ua)
                os_name = inferred_name
                if not os_version:
                    os_version = inferred_ver
            ip_addr = _get_client_ip(request)

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
            # AUDIT FIX #8: Restrict Viewer role to safe permissions only
            viewer, _ = Group.objects.get_or_create(name='Viewer')
            from django.contrib.auth.models import Permission
            from django.contrib.contenttypes.models import ContentType
            
            # Only grant safe app permissions (exclude auth, admin, sessions)
            safe_apps = ['onchannels', 'series', 'live']
            safe_content_types = ContentType.objects.filter(app_label__in=safe_apps)
            safe_view_perms = Permission.objects.filter(
                content_type__in=safe_content_types,
                codename__startswith='view_'
            )
            viewer.permissions.add(*safe_view_perms)
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

        # Require OTP for password change
        otp = (request.data.get("otp") or "").strip()
        if not otp:
            return Response({"detail": "otp is required."}, status=status.HTTP_400_BAD_REQUEST)
        now = timezone.now()
        try:
            t = ActionToken.objects.select_related("user").get(
                user=request.user,
                purpose=ActionToken.PURPOSE_CONFIRM_PASSWORD_CHANGE,
                token=otp,
                used=False,
                expires_at__gt=now,
            )
        except ActionToken.DoesNotExist:
            return Response({"detail": "Invalid or expired code."}, status=status.HTTP_400_BAD_REQUEST)

        # Verify current password
        if not request.user.check_password(current_password):
            return Response({"detail": "Current password is incorrect."}, status=status.HTTP_400_BAD_REQUEST)

        # Validate new password strength
        try:
            validate_password(new_password, user=request.user)
        except Exception as e:
            # Parse validation errors into user-friendly format
            if hasattr(e, 'messages'):
                errors = list(e.messages)
                return Response(
                    {
                        "detail": "Password does not meet requirements.",
                        "errors": errors,
                        "requirements": [
                            "At least 8 characters",
                            "At least one uppercase letter",
                            "At least one lowercase letter",
                            "At least one number",
                            "At least one special character",
                        ]
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        # Mark OTP as used
        try:
            t.used = True
            t.save(update_fields=["used"])
        except Exception:
            pass

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


class RequestSecurityOtpView(APIView):
    """Send a 6-digit OTP to the authenticated user's verified email for
    confirming sensitive actions (change/enable password)."""

    permission_classes = [IsAuthenticated]

    @swagger_auto_schema(
        operation_id="me_request_security_otp",
        tags=["Auth"],
    )
    @ratelimit(key="user_or_ip", rate="3/h", block=False)
    def post(self, request):
        if getattr(request, "limited", False):
            return Response({"detail": "Too many requests. Please try again later."}, status=status.HTTP_429_TOO_MANY_REQUESTS)

        purpose_in = (request.data.get("purpose") or "").strip()
        if purpose_in not in ("change_password", "enable_password"):
            return Response({"detail": "Invalid purpose."}, status=status.HTTP_400_BAD_REQUEST)

        # Ensure user has verified email
        try:
            profile, _ = UserProfile.objects.get_or_create(user=request.user)
            if not getattr(profile, "email_verified", False):
                return Response({"detail": "Email must be verified to perform this action."}, status=status.HTTP_400_BAD_REQUEST)
        except Exception:
            return Response({"detail": "Email must be verified to perform this action."}, status=status.HTTP_400_BAD_REQUEST)

        if purpose_in == "change_password":
            token_purpose = ActionToken.PURPOSE_CONFIRM_PASSWORD_CHANGE
            subject = "Confirm password change"
            intro = "Use this code to confirm your password change on Ontime."
        else:
            token_purpose = ActionToken.PURPOSE_CONFIRM_PASSWORD_ENABLE
            subject = "Confirm enabling password login"
            intro = "Use this code to confirm enabling password login on Ontime."

        # Create OTP
        import random
        otp_code = ''.join([str(random.randint(0, 9)) for _ in range(6)])
        now = timezone.now()
        expires_at = now + timezone.timedelta(minutes=15)
        ActionToken.objects.create(
            user=request.user,
            purpose=token_purpose,
            token=otp_code,
            expires_at=expires_at,
        )

        message = (
            f"{intro}\n\n"
            f"Your verification code is: {otp_code}\n\n"
            "If you did not request this, you can ignore this email. This code expires in 15 minutes."
        )
        html_message = f"""
        <html><body style='font-family: Arial, sans-serif;'>
        <h3>{subject}</h3>
        <p>{intro}</p>
        <div style='font-size: 28px; font-weight: bold; letter-spacing: 6px; padding: 12px 16px; border: 1px dashed #999; display: inline-block;'>
            {otp_code}
        </div>
        <p style='color:#666'>This code expires in 15 minutes.</p>
        </body></html>
        """
        try:
            send_mail(
                subject,
                message,
                settings.DEFAULT_FROM_EMAIL,
                [request.user.email],
                html_message=html_message,
                fail_silently=False,
            )
        except Exception:
            pass

        return Response({"detail": "Verification code sent."}, status=status.HTTP_200_OK)


class EnablePasswordView(APIView):
    """Allow an authenticated user to enable password login on their account.

    This is primarily for accounts that were created via social login and
    currently have no usable password set.
    """

    permission_classes = [IsAuthenticated]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="me_enable_password",
        tags=["Auth"],
    )
    def post(self, request):
        tenant = getattr(request, "tenant", None)
        if tenant is None:
            return Response({"detail": "Unknown tenant."}, status=status.HTTP_400_BAD_REQUEST)

        user = request.user
        # Require a verified email before enabling password login so that
        # password-based access is only allowed on accounts with a confirmed
        # recovery channel.
        try:
            from .models import UserProfile as _UserProfileForCheck

            profile, _ = _UserProfileForCheck.objects.get_or_create(user=user)
            if not getattr(profile, "email_verified", False):
                return Response(
                    {"detail": "Email must be verified before enabling password login."},
                    status=status.HTTP_400_BAD_REQUEST,
                )
        except Exception:
            # If profile lookup fails, fall back to a conservative denial.
            return Response(
                {"detail": "Email must be verified before enabling password login."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        new_password = request.data.get("new_password") or ""
        if not new_password:
            return Response({"detail": "new_password is required."}, status=status.HTTP_400_BAD_REQUEST)

        # If password is already enabled, advise the client to use change-password instead.
        if user.has_usable_password():
            return Response(
                {"detail": "Password is already set for this account. Use change-password instead."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        # Require OTP for enabling password
        otp = (request.data.get("otp") or "").strip()
        if not otp:
            return Response({"detail": "otp is required."}, status=status.HTTP_400_BAD_REQUEST)
        now = timezone.now()
        try:
            t = ActionToken.objects.select_related("user").get(
                user=user,
                purpose=ActionToken.PURPOSE_CONFIRM_PASSWORD_ENABLE,
                token=otp,
                used=False,
                expires_at__gt=now,
            )
        except ActionToken.DoesNotExist:
            return Response({"detail": "Invalid or expired code."}, status=status.HTTP_400_BAD_REQUEST)

        # Validate password strength
        try:
            validate_password(new_password, user=user)
        except Exception as e:
            if hasattr(e, 'messages'):
                errors = list(e.messages)
                return Response(
                    {
                        "detail": "Password does not meet requirements.",
                        "errors": errors,
                        "requirements": [
                            "At least 8 characters",
                            "At least one uppercase letter",
                            "At least one lowercase letter",
                            "At least one number",
                            "At least one special character",
                        ]
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        # Mark OTP as used
        try:
            t.used = True
            t.save(update_fields=["used"])
        except Exception:
            pass

        user.set_password(new_password)
        user.save()

        # Revoke all sessions so the new password becomes the only valid credential
        try:
            from .models import UserSession as LegacySession

            sessions = list(LegacySession.objects.filter(user=user, is_active=True))
            for s in sessions:
                try:
                    s.revoke("password_enabled")
                except Exception:
                    try:
                        s.is_active = False
                        s.save(update_fields=["is_active"])
                    except Exception:
                        pass
        except Exception:
            pass

        try:
            from user_sessions.models import Session as RefreshSession
            from django.utils import timezone as _tz

            RefreshSession.objects.filter(user=user, revoked_at__isnull=True).update(
                revoked_at=_tz.now(), revoke_reason="password_enabled"
            )
        except Exception:
            pass

        res = Response(
            {"detail": "Password enabled. You have been logged out from all devices."},
            status=status.HTTP_200_OK,
        )
        clear_refresh_cookie(res)
        return res


class DisablePasswordView(APIView):
    """Allow an authenticated user to disable password login for their account.

    This sets an unusable password so that only social login remains. Requires
    the current password for safety.
    """

    permission_classes = [IsAuthenticated]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="me_disable_password",
        tags=["Auth"],
    )
    def post(self, request):
        tenant = getattr(request, "tenant", None)
        if tenant is None:
            return Response({"detail": "Unknown tenant."}, status=status.HTTP_400_BAD_REQUEST)

        user = request.user
        if not user.has_usable_password():
            return Response({"detail": "No password is set for this account."}, status=status.HTTP_200_OK)

        current_password = request.data.get("current_password") or ""
        if not current_password:
            return Response({"detail": "current_password is required."}, status=status.HTTP_400_BAD_REQUEST)

        if not user.check_password(current_password):
            return Response({"detail": "Current password is incorrect."}, status=status.HTTP_400_BAD_REQUEST)

        user.set_unusable_password()
        user.save()

        # Revoke all sessions just like a password change
        try:
            from .models import UserSession as LegacySession

            sessions = list(LegacySession.objects.filter(user=user, is_active=True))
            for s in sessions:
                try:
                    s.revoke("password_disabled")
                except Exception:
                    try:
                        s.is_active = False
                        s.save(update_fields=["is_active"])
                    except Exception:
                        pass
        except Exception:
            pass

        try:
            from user_sessions.models import Session as RefreshSession
            from django.utils import timezone as _tz

            RefreshSession.objects.filter(user=user, revoked_at__isnull=True).update(
                revoked_at=_tz.now(), revoke_reason="password_disabled"
            )
        except Exception:
            pass

        res = Response(
            {"detail": "Password disabled. You have been logged out from all devices."},
            status=status.HTTP_200_OK,
        )
        clear_refresh_cookie(res)
        return res


@method_decorator(ratelimit(key='ip', rate='3/h', method='POST', block=False), name='dispatch')
class RequestPasswordResetView(APIView):
    """Initiate a password reset via email.

    Accepts an email address and, if a matching user exists, sends a one-time
    token that can be used to set a new password. The response is always 200
    for privacy (no user enumeration).
    
    Rate limited to 3 requests/hour per IP to prevent email bombing.
    """

    permission_classes = [AllowAny]

    @swagger_auto_schema(
        operation_id="password_reset_request",
        tags=["Auth"],
    )
    def post(self, request):
        # Check rate limit
        if getattr(request, "limited", False):
            return Response(
                {"detail": "Too many password reset requests. Please wait before trying again."},
                status=status.HTTP_429_TOO_MANY_REQUESTS,
            )
        
        email = (request.data.get("email") or "").strip().lower()
        if not email:
            return Response({"detail": "email is required."}, status=status.HTTP_400_BAD_REQUEST)

        try:
            user = User.objects.get(email__iexact=email)
        except User.DoesNotExist:
            # Do not leak whether the email exists
            return Response({"detail": "If an account exists for this email, a reset link has been sent."})
        
        # Prevent password reset for social-only accounts (no password set)
        # These accounts should use "Enable Password" feature in app settings instead
        if not user.has_usable_password():
            # Return generic message to avoid user enumeration
            # (Don't reveal that this is a social-only account)
            return Response(
                {"detail": "If an account exists for this email, a reset link has been sent."},
                status=status.HTTP_200_OK,
            )

        # Only allow password reset for accounts whose email has been verified.
        # For unverified emails we respond with the same generic message but do
        # not create a token or send mail.
        try:
            from .models import UserProfile as _UserProfileForReset

            profile, _ = _UserProfileForReset.objects.get_or_create(user=user)
            if not getattr(profile, "email_verified", False):
                return Response(
                    {"detail": "If an account exists for this email, a reset link has been sent."},
                    status=status.HTTP_200_OK,
                )
        except Exception:
            # On any profile lookup error, behave as if the email is not eligible
            # for reset while preserving the generic response.
            return Response(
                {"detail": "If an account exists for this email, a reset link has been sent."},
                status=status.HTTP_200_OK,
            )

        # Create a 6-digit OTP valid for 15 minutes (simpler for mobile UX)
        import random

        otp_code = ''.join([str(random.randint(0, 9)) for _ in range(6)])
        now = timezone.now()
        expires_at = now + timezone.timedelta(minutes=15)
        ActionToken.objects.create(
            user=user,
            purpose=ActionToken.PURPOSE_RESET_PASSWORD,
            token=otp_code,
            expires_at=expires_at,
        )

        subject = "Reset your Ontime password"
        
        # Plain text version
        message = (
            "Hello,\n\n"
            "We received a request to reset your Ontime account password.\n\n"
            f"Your password reset code is: {otp_code}\n\n"
            "Enter this code in the app to reset your password.\n\n"
            "If you did not request this, you can safely ignore this email. "
            "This code will expire in 15 minutes."
        )
        
        # HTML version with easy-to-copy code
        html_message = f"""
        <!DOCTYPE html>
        <html>
        <head>
            <meta charset="UTF-8">
        </head>
        <body style="font-family: Arial, sans-serif; line-height: 1.6; color: #333; max-width: 600px; margin: 0 auto; padding: 20px;">
            <div style="background-color: #f8f9fa; border-radius: 10px; padding: 30px; text-align: center;">
                <h2 style="color: #2c3e50; margin-bottom: 20px;">Reset Your Password</h2>
                <p style="font-size: 16px; color: #555; margin-bottom: 30px;">
                    We received a request to reset your Ontime account password.
                </p>
                
                <div style="background-color: white; border: 2px solid #3498db; border-radius: 8px; padding: 20px; margin: 20px 0;">
                    <p style="font-size: 14px; color: #7f8c8d; margin-bottom: 10px; text-transform: uppercase; letter-spacing: 1px;">
                        Your Reset Code
                    </p>
                    <div style="font-size: 42px; font-weight: bold; color: #2c3e50; letter-spacing: 8px; font-family: 'Courier New', monospace; user-select: all;">
                        {otp_code}
                    </div>
                    <p style="font-size: 12px; color: #95a5a6; margin-top: 10px;">
                        Tap to select and copy
                    </p>
                </div>
                
                <p style="font-size: 14px; color: #555; margin-top: 30px;">
                    Enter this code in the app to reset your password.
                </p>
                
                <div style="background-color: #fff3cd; border-left: 4px solid #ffc107; padding: 12px; margin-top: 20px; text-align: left;">
                    <p style="margin: 0; font-size: 13px; color: #856404;">
                        <strong>⏱️ This code expires in 15 minutes</strong><br>
                        If you didn't request this, you can safely ignore this email.
                    </p>
                </div>
            </div>
            
            <p style="font-size: 12px; color: #95a5a6; text-align: center; margin-top: 30px;">
                © 2026 Ontime Ethiopia. All rights reserved.
            </p>
        </body>
        </html>
        """

        try:
            from django.core.mail import EmailMultiAlternatives
            
            email_msg = EmailMultiAlternatives(
                subject,
                message,  # Plain text fallback
                settings.DEFAULT_FROM_EMAIL,
                [email],
            )
            email_msg.attach_alternative(html_message, "text/html")
            email_msg.send(fail_silently=False)
        except Exception:
            return Response(
                {"detail": "Could not send password reset email.", "error": "email_send_failed"},
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )

        return Response(
            {"detail": "If an account exists for this email, a reset link has been sent."},
            status=status.HTTP_200_OK,
        )


class VerifyPasswordResetCodeView(APIView):
    """Verify a password reset OTP code without consuming it.
    
    This allows the mobile app to validate the code before navigating
    to the password entry screen, improving UX.
    """
    
    permission_classes = [AllowAny]
    
    @swagger_auto_schema(
        operation_id="password_reset_verify_code",
        tags=["Auth"],
    )
    def post(self, request):
        token_str = (request.data.get("token") or "").strip()
        
        if not token_str:
            return Response(
                {"detail": "token is required.", "valid": False},
                status=status.HTTP_400_BAD_REQUEST,
            )
        
        now = timezone.now()
        try:
            # Check if token exists and is valid (but don't mark as used)
            ActionToken.objects.get(
                token=token_str,
                purpose=ActionToken.PURPOSE_RESET_PASSWORD,
                used=False,
                expires_at__gt=now,
            )
            return Response({"detail": "Code is valid.", "valid": True}, status=status.HTTP_200_OK)
        except ActionToken.DoesNotExist:
            return Response(
                {"detail": "Invalid or expired code.", "valid": False},
                status=status.HTTP_400_BAD_REQUEST,
            )


class ConfirmPasswordResetView(APIView):
    """Confirm a password reset using a one-time token.

    This endpoint is intended for both web and mobile clients. It accepts a
    token and a new password in the request body.
    """

    permission_classes = [AllowAny]

    @swagger_auto_schema(
        operation_id="password_reset_confirm",
        tags=["Auth"],
    )
    def post(self, request):
        token_str = (request.data.get("token") or "").strip()
        new_password = request.data.get("new_password") or ""

        if not token_str or not new_password:
            return Response(
                {"detail": "token and new_password are required."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        now = timezone.now()
        try:
            t = ActionToken.objects.select_related("user").get(
                token=token_str,
                purpose=ActionToken.PURPOSE_RESET_PASSWORD,
                used=False,
                expires_at__gt=now,
            )
        except ActionToken.DoesNotExist:
            return Response(
                {"detail": "Invalid or expired token."},
                status=status.HTTP_400_BAD_REQUEST,
            )

        user = t.user

        # Validate new password strength
        try:
            validate_password(new_password, user=t.user)
        except Exception as e:
            if hasattr(e, 'messages'):
                errors = list(e.messages)
                return Response(
                    {
                        "detail": "Password does not meet requirements.",
                        "errors": errors,
                        "requirements": [
                            "At least 8 characters",
                            "At least one uppercase letter",
                            "At least one lowercase letter",
                            "At least one number",
                            "At least one special character",
                        ]
                    },
                    status=status.HTTP_400_BAD_REQUEST,
                )
            return Response({"detail": str(e)}, status=status.HTTP_400_BAD_REQUEST)

        # Set new password and mark token used
        user.set_password(new_password)
        user.save()
        t.used = True
        t.save(update_fields=["used"])

        # Revoke all sessions for security, similar to ChangePasswordView
        try:
            from .models import UserSession as LegacySession

            sessions = list(LegacySession.objects.filter(user=user, is_active=True))
            for s in sessions:
                try:
                    s.revoke("password_reset")
                except Exception:
                    try:
                        s.is_active = False
                        s.save(update_fields=["is_active"])
                    except Exception:
                        pass
        except Exception:
            pass

        try:
            from user_sessions.models import Session as RefreshSession
            from django.utils import timezone as _tz

            RefreshSession.objects.filter(user=user, revoked_at__isnull=True).update(
                revoked_at=_tz.now(), revoke_reason="password_reset",
            )
        except Exception:
            pass

        # No cookies to clear here since this is typically called unauthenticated
        return Response(
            {"detail": "Password has been reset. Please sign in with your new password."},
            status=status.HTTP_200_OK,
        )

class DeleteMeView(APIView):
    """Allow the authenticated user to delete their own account.

    We implement this as an anonymization + deactivation step so that
    existing content (comments, reactions, notifications) can remain
    without being clearly tied to a real identity.
    """

    permission_classes = [IsAuthenticated]

    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="me_delete_account",
        tags=["Auth"],
    )
    def post(self, request):
        tenant = getattr(request, "tenant", None)
        if tenant is None:
            return Response({"detail": "Unknown tenant."}, status=status.HTTP_400_BAD_REQUEST)

        user = request.user

        # Best-effort anonymization for the default Django User model.
        try:
            anon_username = f"deleted_user_{user.id}" if getattr(user, "id", None) is not None else "deleted_user"
            # Ensure we do not collide with existing usernames.
            base_username = anon_username
            suffix = 1
            while User.objects.filter(username=anon_username).exclude(pk=user.pk).exists():
                anon_username = f"{base_username}_{suffix}"
                suffix += 1

            user.username = anon_username

            # Decide whether to clear PII based on whether this user has
            # linked social accounts. For social users we clear email and
            # names so they can later sign up again with the same provider
            # and email. For password-only users we keep their email and
            # names but still deactivate the account.
            try:
                from .models import SocialAccount as _SocialAccountForCheck

                has_social = _SocialAccountForCheck.objects.filter(user=user).exists()
            except Exception:
                has_social = False

            if has_social:
                user.first_name = ""
                user.last_name = ""
                user.email = ""

            try:
                user.is_active = False
            except Exception:
                pass
            user.save()
        except Exception:
            # If anonymization fails we still proceed to revoke sessions
            # and clear cookies to ensure logout, but we do not surface
            # internal errors to the client.
            pass

        # Best-effort: detach any linked social accounts so that a future
        # social login (with the same provider_id/email) can create a fresh
        # user instead of reusing this disabled/anonymized one.
        try:
            from .models import SocialAccount as _SocialAccount

            _SocialAccount.objects.filter(user=user).delete()
        except Exception:
            # If this fails, the social login flow may continue to see the
            # disabled account and return "Account is disabled" until the
            # social link is removed manually.
            pass

        # Revoke all sessions for this user in legacy UserSession table.
        try:
            from .models import UserSession as LegacySession
            sessions = list(LegacySession.objects.filter(user=user, is_active=True))
            for s in sessions:
                try:
                    s.revoke("user_deleted")
                except Exception:
                    try:
                        s.is_active = False
                        s.save(update_fields=["is_active"])
                    except Exception:
                        pass
        except Exception:
            pass

        # Revoke all sessions in new user_sessions backend.
        try:
            from user_sessions.models import Session as RefreshSession
            from django.utils import timezone as _tz

            RefreshSession.objects.filter(user=user, revoked_at__isnull=True).update(
                revoked_at=_tz.now(), revoke_reason="user_deleted"
            )
        except Exception:
            pass

        res = Response({"detail": "Account deleted and anonymized. You have been logged out from all devices."}, status=status.HTTP_200_OK)
        clear_refresh_cookie(res)
        return res
