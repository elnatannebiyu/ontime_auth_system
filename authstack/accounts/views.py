from django.conf import settings
from django.contrib.auth.models import User
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework import status
from rest_framework.permissions import IsAuthenticated
from rest_framework_simplejwt.views import TokenObtainPairView, TokenRefreshView
from .serializers import MeSerializer, CookieTokenObtainPairSerializer
from .permissions import HasAnyRole, DjangoPermissionRequired, ReadOnlyOrPerm

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
    serializer_class = CookieTokenObtainPairSerializer

    def post(self, request, *args, **kwargs):
        res = super().post(request, *args, **kwargs)
        if res.status_code == 200 and "refresh" in res.data:
            refresh = res.data.pop("refresh")
            set_refresh_cookie(res, refresh)
        return res


class CookieTokenRefreshView(TokenRefreshView):
    def post(self, request, *args, **kwargs):
        data = request.data.copy()
        data["refresh"] = request.COOKIES.get(REFRESH_COOKIE_NAME)
        request._full_data = data
        res = super().post(request, *args, **kwargs)
        if res.status_code == 200 and "refresh" in res.data:
            new_refresh = res.data.pop("refresh")
            set_refresh_cookie(res, new_refresh)
        return res


class LogoutView(APIView):
    def post(self, request):
        res = Response({"detail": "Logged out."}, status=status.HTTP_200_OK)
        clear_refresh_cookie(res)
        return res


class MeView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        return Response(MeSerializer(request.user).data)


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
