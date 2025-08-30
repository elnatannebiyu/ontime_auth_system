from django.urls import path
from .views import (
    TokenObtainPairWithCookieView,
    CookieTokenRefreshView,
    LogoutView,
    MeView,
    AdminOnlyView,
    UserWriteView,
    RegisterView,
)

urlpatterns = [
    path("token/", TokenObtainPairWithCookieView.as_view(), name="token_obtain_pair"),
    path("token/refresh/", CookieTokenRefreshView.as_view(), name="token_refresh"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("register/", RegisterView.as_view(), name="register"),

    path("me/", MeView.as_view(), name="me"),
    path("admin-only/", AdminOnlyView.as_view(), name="admin_only"),
    path("users/", UserWriteView.as_view(), name="users"),
]
