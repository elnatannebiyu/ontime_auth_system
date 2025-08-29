from django.urls import path
from .views import (
    CookieTokenObtainPairView,
    CookieTokenRefreshView,
    LogoutView,
    MeView,
    AdminOnlyView,
    UserWriteView,
)

urlpatterns = [
    path("token/", CookieTokenObtainPairView.as_view(), name="token_obtain_pair"),
    path("token/refresh/", CookieTokenRefreshView.as_view(), name="token_refresh"),
    path("logout/", LogoutView.as_view(), name="logout"),

    path("me/", MeView.as_view(), name="me"),
    path("admin-only/", AdminOnlyView.as_view(), name="admin_only"),
    path("users/", UserWriteView.as_view(), name="users"),
]
