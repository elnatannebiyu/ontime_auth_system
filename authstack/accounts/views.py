from django.conf import settings
from django.contrib.auth.models import User
from django.contrib.auth.models import Group
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated, AllowAny
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from rest_framework_simplejwt.serializers import TokenRefreshSerializer
from .serializers import MeSerializer, CookieTokenObtainPairSerializer, RegistrationSerializer
from .permissions import (
    HasAnyRole,
    DjangoPermissionRequired,
    ReadOnlyOrPerm,
    IsTenantMember,
    TenantMatchesToken,
)

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


class CookieTokenObtainPairView(TokenObtainPairView):
    permission_classes = [AllowAny]
    serializer_class = CookieTokenObtainPairSerializer

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
    def post(self, request, *args, **kwargs):
        refresh = request.data.get("refresh") or request.COOKIES.get(REFRESH_COOKIE_NAME)
        if not refresh:
            return Response({"detail": "No refresh token."}, status=status.HTTP_400_BAD_REQUEST)

        ser = TokenRefreshSerializer(data={"refresh": refresh})
        ser.is_valid(raise_exception=True)
        data = ser.validated_data

        resp = Response(data, status=status.HTTP_200_OK)
        new_refresh = data.get("refresh")
        if new_refresh:
            # move refresh to httpOnly cookie and omit from JSON
            set_refresh_cookie(resp, new_refresh)
            resp.data.pop("refresh", None)
        return resp


class LogoutView(APIView):
    def post(self, request):
        res = Response({"detail": "Logged out."}, status=status.HTTP_200_OK)
        clear_refresh_cookie(res)
        return res


class MeView(APIView):
    permission_classes = [IsTenantMember, TenantMatchesToken]

    def get(self, request):
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

    def get(self, request):
        return Response({"ok": True, "msg": "Hello, Administrator!"})


class UserWriteView(APIView):
    """Read allowed to any authenticated user; write requires 'auth.change_user'."""
    permission_classes = [ReadOnlyOrPerm]
    def get_permissions(self):
        p = super().get_permissions()[0]
        p.required_perm = "auth.change_user"
        return [p]

    def get(self, request):
        users = list(User.objects.values("id", "username", "email")[:25])
        return Response({"results": users})

    def post(self, request):
        # Example write that requires the perm
        return Response({"ok": True, "action": "Would write something"})


class RegisterView(APIView):
    permission_classes = [AllowAny]

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
