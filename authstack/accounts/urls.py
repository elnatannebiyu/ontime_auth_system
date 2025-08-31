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
from .views_sessions import (
    SessionListView,
    SessionDetailView,
    RevokeAllSessionsView,
)
from .views_social import (
    social_login_view,
    link_social_account_view,
    unlink_social_account_view,
)
from . import form_views
from .form_config import get_form_config_view

urlpatterns = [
    path("token/", TokenObtainPairWithCookieView.as_view(), name="token_obtain_pair"),
    path("token/refresh/", CookieTokenRefreshView.as_view(), name="token_refresh"),
    path("logout/", LogoutView.as_view(), name="logout"),
    path("register/", RegisterView.as_view(), name="register"),

    path("me/", MeView.as_view(), name="me"),
    path("admin-only/", AdminOnlyView.as_view(), name="admin_only"),
    path("users/", UserWriteView.as_view(), name="users"),
    
    # Social authentication
    path('social/login/', social_login_view, name='social_login'),
    path('social/link/', link_social_account_view, name='link_social'),
    path('social/unlink/<str:provider>/', unlink_social_account_view, name='unlink_social'),
    
    # Dynamic forms API
    path('forms/schema/', form_views.get_form_schema_view, name='form_schema'),
    path('forms/validate/', form_views.validate_field_view, name='validate_field'),
    path('forms/submit/', form_views.submit_dynamic_form_view, name='submit_form'),
    path('forms/config/', get_form_config_view, name='form_config'),
    
    # Session management
    path('sessions/', SessionListView.as_view(), name='session_list'),
    path('sessions/<uuid:session_id>/', SessionDetailView.as_view(), name='session_detail'),
    path('sessions/revoke-all/', RevokeAllSessionsView.as_view(), name='revoke_all_sessions'),
]
