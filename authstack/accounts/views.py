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
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.tokens import RefreshToken
from rest_framework_simplejwt.exceptions import TokenError
from accounts.jwt_auth import CustomTokenObtainPairSerializer, RefreshTokenRotation
from .serializers import CookieTokenObtainPairSerializer, RegistrationSerializer, MeSerializer
from .permissions import (
    HasAnyRole,
    DjangoPermissionRequired,
    ReadOnlyOrPerm,
    IsTenantMember,
    TenantMatchesToken,
)
from drf_yasg import openapi
from drf_yasg.utils import swagger_auto_schema

REFRESH_COOKIE_NAME = getattr(settings, "REFRESH_COOKIE_NAME", "refresh_token")
REFRESH_COOKIE_PATH = getattr(settings, "REFRESH_COOKIE_PATH", "/api/token/refresh/")


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
    rate = '3/hour'
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
        # Get refresh token from cookie
        refresh_token = request.COOKIES.get('refresh_token')
        
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
            
            # Set new refresh token in cookie
            response.set_cookie(
                'refresh_token',
                new_tokens['refresh'],
                max_age=60 * 60 * 24 * 7,  # 7 days
                httponly=True,
                secure=settings.DEBUG is False,
                samesite='Strict'
            )
            
            return response
            
        except Exception as e:
            return Response(
                {"detail": str(e)},
                status=status.HTTP_401_UNAUTHORIZED
            )


class LogoutView(APIView):
    @swagger_auto_schema(
        manual_parameters=[TokenObtainPairWithCookieView.PARAM_TENANT],
        operation_id="logout_create",
        tags=["Auth"],
    )
    def post(self, request):
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


@method_decorator(ratelimit(key='ip', rate='3/h', method='POST'), name='dispatch')
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

        # Assign default role 'Viewer' if it exists
        viewer = Group.objects.filter(name="Viewer").first()
        if viewer is not None:
            membership.roles.add(viewer)

        # Build JWTs similar to CookieTokenObtainPairSerializer behavior
        token_ser = CookieTokenObtainPairSerializer()
        refresh = token_ser.get_token(user)
        access = refresh.access_token
        access["tenant_id"] = tenant.slug
        member_roles = list(membership.roles.values_list("name", flat=True))
        access["tenant_roles"] = member_roles

        resp = Response({"access": str(access)}, status=status.HTTP_201_CREATED)
        set_refresh_cookie(resp, str(refresh))
        return resp
