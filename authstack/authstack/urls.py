import os
from django.contrib import admin
from django.urls import path, re_path, include
from django.conf import settings
from django.conf.urls.static import static
from rest_framework import permissions

# Swagger imports guarded to avoid hard dependency in production
_ENABLE_SWAGGER = getattr(settings, 'ENABLE_SWAGGER', False) or settings.DEBUG
try:
    if _ENABLE_SWAGGER:
        from drf_yasg.views import get_schema_view  # type: ignore
        from drf_yasg import openapi  # type: ignore
    else:
        get_schema_view = None  # type: ignore
        openapi = None  # type: ignore
except Exception:
    # drf_yasg (and pkg_resources) not available; disable swagger routes
    get_schema_view = None  # type: ignore
    openapi = None  # type: ignore

if get_schema_view and openapi:
    schema_view = get_schema_view(
        openapi.Info(
            title="AuthStack API",
            default_version="v1",
            description="JWT Authentication API with roles and permissions",
            contact=openapi.Contact(email="admin@example.com"),
        ),
        public=True,
        permission_classes=[permissions.AllowAny],
    )
else:
    schema_view = None

# AUDIT FIX #4: Obscure admin URL to reduce attack surface
# Set via environment variable ADMIN_URL_PATH (default: secret-admin-panel)
ADMIN_URL_PATH = os.environ.get('ADMIN_URL_PATH', 'secret-admin-panel')

urlpatterns = [
    path(f"{ADMIN_URL_PATH}/", admin.site.urls),
    path("api/", include("accounts.urls")),
    path("api/channels/", include("onchannels.urls")),
    path("api/auth/otp/", include("otp_auth.urls")),
    path("api/series/", include("series.urls")),
    path("api/live/", include("live.urls")),
    path("api/user-sessions/", include("user_sessions.urls")),
]

if schema_view:
    # Swagger/OpenAPI documentation
    urlpatterns += [
        re_path(r"^swagger(?P<format>\.json|\.yaml)$", schema_view.without_ui(cache_timeout=0), name="schema-json"),
        path("swagger/", schema_view.with_ui("swagger", cache_timeout=0), name="schema-swagger-ui"),
        path("redoc/", schema_view.with_ui("redoc", cache_timeout=0), name="schema-redoc"),
    ]

# Serve user-uploaded media files in development
if settings.DEBUG:
    urlpatterns += static(settings.MEDIA_URL, document_root=settings.MEDIA_ROOT)
