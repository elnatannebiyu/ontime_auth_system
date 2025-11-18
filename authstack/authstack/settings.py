from pathlib import Path
import os
from datetime import timedelta
from corsheaders.defaults import default_headers, default_methods

BASE_DIR = Path(__file__).resolve().parent.parent
SECRET_KEY = os.environ.get(
    "DJANGO_SECRET_KEY", "django-insecure-change-this-in-production-@#$%^&*()"
)
DEBUG = os.environ.get("DJANGO_DEBUG", "False").lower() in ("1", "true", "yes")
ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "*").split(",")

# Allow classic username/password flows when True. Set to False to enforce social-only login.
AUTH_ALLOW_PASSWORD = os.environ.get("AUTH_ALLOW_PASSWORD", "True").lower() in ("1", "true", "yes")

# Comma-separated list of allowed email domains for email/password auth (registration and optional login)
# Default to Gmail domains; set to empty to disable allowlist enforcement in validators
EMAIL_ALLOWED_DOMAINS = [
    d.strip().lower()
    for d in os.environ.get("EMAIL_ALLOWED_DOMAINS", "gmail.com,googlemail.com").split(",")
    if d.strip()
]

INSTALLED_APPS = [
    'django.contrib.admin',
    'django.contrib.auth',
    'django.contrib.contenttypes',
    'django.contrib.sessions',
    'django.contrib.messages',
    'django.contrib.staticfiles',
    'rest_framework',
    'rest_framework_simplejwt',
    'corsheaders',
    'drf_yasg',
    # 'django_ratelimit',  # Temporarily disabled due to cache backend issues
    'axes',
    'accounts',
    'onchannels',
    'user_sessions',
    'otp_auth',
    'tenants',
    'series',
    'live.apps.LiveConfig',
    'django_celery_beat',
]

# Dev-only utilities
if DEBUG:
    INSTALLED_APPS += ['django_extensions']

MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    "whitenoise.middleware.WhiteNoiseMiddleware",
    "corsheaders.middleware.CorsMiddleware",
    "django.contrib.sessions.middleware.SessionMiddleware",
    "django.middleware.common.CommonMiddleware",
    # Dev-only helper: normalize raw JWT Authorization header to include 'Bearer '
    # Placed before TenantResolverMiddleware so our debug logs display the normalized header
    "common.tenancy.AuthorizationHeaderNormalizerMiddleware",
    "common.tenancy.TenantResolverMiddleware",
    # Enforce minimum supported app version (returns HTTP 426 for outdated builds)
    "common.middleware.version_enforce.AppVersionEnforceMiddleware",
    "accounts.middleware.SessionRevocationMiddleware",  # Check session revocation early
    "django.middleware.csrf.CsrfViewMiddleware",
    "django.contrib.auth.middleware.AuthenticationMiddleware",
    "django.contrib.messages.middleware.MessageMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    "axes.middleware.AxesMiddleware",  # Brute force protection
]

ROOT_URLCONF = "authstack.urls"
TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {
            "context_processors": [
                "django.template.context_processors.debug",
                "django.template.context_processors.request",
                "django.contrib.auth.context_processors.auth",
                "django.contrib.messages.context_processors.messages",
            ],
        },
    },
]
WSGI_APPLICATION = "authstack.wsgi.application"
ASGI_APPLICATION = "authstack.asgi.application"

DATABASES = {
    "default": {
        "ENGINE": "django.db.backends.sqlite3",
        "NAME": BASE_DIR / "db.sqlite3",
    }
}

# Celery configuration
CELERY_BROKER_URL = os.environ.get('CELERY_BROKER_URL', 'redis://localhost:6379/2')
CELERY_RESULT_BACKEND = os.environ.get('CELERY_RESULT_BACKEND', 'redis://localhost:6379/2')
CELERY_ACCEPT_CONTENT = ['json']
CELERY_TASK_SERIALIZER = 'json'
CELERY_RESULT_SERIALIZER = 'json'
CELERY_TIMEZONE = os.environ.get('CELERY_TIMEZONE', 'Africa/Addis_Ababa')
CELERY_BROKER_TRANSPORT_OPTIONS = {
    'global_keyprefix': os.environ.get('CELERY_KEY_PREFIX', 'celery-shorts:')
}
CELERY_RESULT_BACKEND_TRANSPORT_OPTIONS = {
    'global_keyprefix': os.environ.get('CELERY_KEY_PREFIX', 'celery-shorts:')
}

# Celery Beat schedule
from celery.schedules import crontab  # type: ignore
CELERY_BEAT_SCHEDULE = {
    'dispatch-due-notifications': {
        'task': 'onchannels.tasks.dispatch_due_notifications',
        'schedule': 60.0,  # every minute
    },
    'evict-shorts-low-water': {
        'task': 'onchannels.tasks.evict_shorts_low_water',
        'schedule': 60.0 * 15,  # every 15 minutes
    },
}
CELERY_BEAT_SCHEDULER = 'django_celery_beat.schedulers:DatabaseScheduler'

# Cache configuration for rate limiting
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.db.DatabaseCache',
        'LOCATION': 'django_cache_table',
    }
}

# Django-ratelimit configuration
RATELIMIT_USE_CACHE = 'default'
RATELIMIT_ENABLE = True

AUTH_PASSWORD_VALIDATORS = [
    {
        "NAME": "django.contrib.auth.password_validation.UserAttributeSimilarityValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.MinimumLengthValidator",
        "OPTIONS": {
            "min_length": 8,
        }
    },
    {
        "NAME": "django.contrib.auth.password_validation.CommonPasswordValidator",
    },
    {
        "NAME": "django.contrib.auth.password_validation.NumericPasswordValidator",
    },
    {
        "NAME": "accounts.validators.CustomPasswordValidator",
    },
]

LANGUAGE_CODE = "en-us"
TIME_ZONE = "Africa/Addis_Ababa"
USE_I18N = True
USE_TZ = True

STATIC_URL = "static/"
STATIC_ROOT = BASE_DIR / "staticfiles"
STATICFILES_STORAGE = "whitenoise.storage.CompressedManifestStaticFilesStorage"
MEDIA_URL = "/media/"
MEDIA_ROOT = os.environ.get('MEDIA_ROOT', '/srv/media/short/videos')
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

# Email settings
EMAIL_BACKEND = 'django.core.mail.backends.console.EmailBackend' if DEBUG else 'django.core.mail.backends.smtp.EmailBackend'
EMAIL_HOST = os.environ.get('EMAIL_HOST', 'smtp.gmail.com')
EMAIL_PORT = int(os.environ.get('EMAIL_PORT', '587'))
EMAIL_USE_TLS = os.environ.get('EMAIL_USE_TLS', 'True') == 'True'
EMAIL_HOST_USER = os.environ.get('EMAIL_HOST_USER', '')
EMAIL_HOST_PASSWORD = os.environ.get('EMAIL_HOST_PASSWORD', '')
DEFAULT_FROM_EMAIL = os.environ.get('DEFAULT_FROM_EMAIL', 'noreply@ontime.com')

# SMS settings (Twilio) - for future use
TWILIO_ACCOUNT_SID = os.environ.get('TWILIO_ACCOUNT_SID', '')
TWILIO_AUTH_TOKEN = os.environ.get('TWILIO_AUTH_TOKEN', '')
TWILIO_PHONE_NUMBER = os.environ.get('TWILIO_PHONE_NUMBER', '')

REST_FRAMEWORK = {
    'DEFAULT_AUTHENTICATION_CLASSES': (
        'accounts.jwt_auth.CustomJWTAuthentication',
    ),
    "DEFAULT_PERMISSION_CLASSES": (
        "rest_framework.permissions.IsAuthenticated",
    ),
    "DEFAULT_PAGINATION_CLASS": "rest_framework.pagination.PageNumberPagination",
    "PAGE_SIZE": 20,
    # Rate limiting
    "DEFAULT_THROTTLE_CLASSES": [
        "rest_framework.throttling.AnonRateThrottle",
        "rest_framework.throttling.UserRateThrottle",
    ],
    "DEFAULT_THROTTLE_RATES": {
        "anon": "20/hour",  # Anonymous users
        "user": "1000/hour",  # Authenticated users
        "login": "5/minute",  # Login attempts
        "register": "3/hour",  # Registration attempts
    },
}

# CORS/CSRF for React
CORS_ALLOWED_ORIGINS = [
    "http://localhost:5173",
    "http://localhost:3000",
]
CORS_ALLOW_CREDENTIALS = True
_cors_env = os.environ.get("CORS_ALLOWED_ORIGINS")
if _cors_env:
    CORS_ALLOWED_ORIGINS = [o.strip() for o in _cors_env.split(",") if o.strip()]
CSRF_TRUSTED_ORIGINS = [
    "http://localhost:5173",
    "http://localhost:3000",
]
_csrf_env = os.environ.get("CSRF_TRUSTED_ORIGINS")
if _csrf_env:
    CSRF_TRUSTED_ORIGINS = [o.strip() for o in _csrf_env.split(",") if o.strip()]

# Allow custom headers used by the admin frontend
CORS_ALLOW_HEADERS = list(default_headers) + [
    'x-tenant-id',
    'x-admin-login',
]
# Methods (use defaults, but make explicit for clarity)
CORS_ALLOW_METHODS = list(default_methods)

# SimpleJWT
SIMPLE_JWT = {
    "ACCESS_TOKEN_LIFETIME": timedelta(minutes=15),
    "REFRESH_TOKEN_LIFETIME": timedelta(days=7),
    "ROTATE_REFRESH_TOKENS": True,
    "BLACKLIST_AFTER_ROTATION": True,
    "AUTH_HEADER_TYPES": ("Bearer",),
}

# Refresh cookie constants
REFRESH_COOKIE_NAME = "refresh_token"
REFRESH_COOKIE_PATH = "/api/token/refresh/"

# YouTube API key (set via environment)
YOUTUBE_API_KEY = os.getenv("YOUTUBE_API_KEY")

# Swagger UI: declare Bearer auth so the Authorize button accepts JWT tokens
SWAGGER_SETTINGS = {
    "SECURITY_DEFINITIONS": {
        "Bearer": {
            "type": "apiKey",
            "name": "Authorization",
            "in": "header",
            "description": "JWT Authorization header using the Bearer scheme. Example: 'Bearer {token}'",
        },
        # Allow setting the multi-tenant header via the Authorize dialog
        "Tenant": {
            "type": "apiKey",
            "name": "X-Tenant-Id",
            "in": "header",
            "description": "Tenant identifier (e.g., ontime). Required for all /api/ endpoints.",
        },
    },
    # Ensure all operations include these security schemes so Swagger UI sends the headers
    # after you click Authorize.
    "SECURITY_REQUIREMENTS": [
        {"Bearer": [], "Tenant": []}
    ],
}

# Console logging (enable DEBUG for common.tenancy to trace tenant resolution)
# Django-axes configuration for brute force protection
AXES_FAILURE_LIMIT = 5  # Lock after 5 failed attempts
AXES_COOLOFF_TIME = 1  # Cooloff period in hours
AXES_LOCKOUT_PARAMETERS = [[ "ip_address"]]  # Lock by username+IP combo
AXES_RESET_ON_SUCCESS = True
AXES_ENABLE_ACCESS_FAILURE_LOG = True
AXES_LOCKOUT_TEMPLATE = None  # Return 403 instead of template
AXES_VERBOSE = True

# Add axes backend for authentication
AUTHENTICATION_BACKENDS = [
    'axes.backends.AxesStandaloneBackend',
    'django.contrib.auth.backends.ModelBackend',
]

# Cache configuration for rate limiting
CACHES = {
    'default': {
        'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
        'LOCATION': 'unique-snowflake',
    }
}

LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "console": {"class": "logging.StreamHandler"},
    },
    "loggers": {
        # Our middleware in `common/tenancy.py`
        "common.tenancy": {
            "handlers": ["console"],
            "level": "DEBUG",
            "propagate": False,
        },
        # Optional: surface Django request warnings/info
        "django.request": {
            "handlers": ["console"],
            "level": "INFO",
            "propagate": False,
        },
    },
}

# Social Auth Settings
GOOGLE_CLIENT_ID = os.environ.get('GOOGLE_CLIENT_ID', '')
GOOGLE_CLIENT_SECRET = os.environ.get('GOOGLE_CLIENT_SECRET', '')

# Optional: allow multiple Google client IDs (e.g., Web + iOS) for audience verification
# Accepts either a comma-separated string or a single value. Defaults to empty list.
_google_additional_raw = os.environ.get('GOOGLE_ADDITIONAL_CLIENT_IDS', '')
if _google_additional_raw:
    if ',' in _google_additional_raw:
        GOOGLE_ADDITIONAL_CLIENT_IDS = [x.strip() for x in _google_additional_raw.split(',') if x.strip()]
    else:
        GOOGLE_ADDITIONAL_CLIENT_IDS = _google_additional_raw.strip()
else:
    GOOGLE_ADDITIONAL_CLIENT_IDS = []

APPLE_CLIENT_ID = os.environ.get('APPLE_CLIENT_ID', '')
APPLE_TEAM_ID = os.environ.get('APPLE_TEAM_ID', '')
APPLE_KEY_ID = os.environ.get('APPLE_KEY_ID', '')
APPLE_PRIVATE_KEY = os.environ.get('APPLE_PRIVATE_KEY', '')

# Explicit allowlist of Google Web OAuth client IDs for social login audience verification
# Include staging/prod IDs here as needed. You can also append via env var GOOGLE_WEB_CLIENT_IDS (comma-separated).
_extra_google_web_ids = set(
    s.strip() for s in os.environ.get('GOOGLE_WEB_CLIENT_IDS', '').split(',') if s.strip()
)
GOOGLE_WEB_CLIENT_IDS = {
    "59310140647-ks91sebo8ccbd9f6m8q065p7vp4uogvm.apps.googleusercontent.com",
    # iOS client ID so tokens issued on iOS are accepted by the backend verifier
    "59310140647-m77nbro0rb4i146mtcq5blpb0n1mn233.apps.googleusercontent.com",
} | _extra_google_web_ids

# Production security settings (tuned via environment; safe defaults under HTTPS)
# Respect reverse proxy SSL (Nginx) so request.is_secure() works
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Enforce HTTPS in production unless explicitly disabled via env
SECURE_SSL_REDIRECT = (
    os.environ.get("SECURE_SSL_REDIRECT", "True").lower() in ("1", "true", "yes")
    if not DEBUG
    else False
)

# Secure cookies in production
SESSION_COOKIE_SECURE = True if not DEBUG else False
CSRF_COOKIE_SECURE = True if not DEBUG else False

# SameSite policy; Lax is a reasonable default for same-site apps
SESSION_COOKIE_SAMESITE = os.environ.get("SESSION_COOKIE_SAMESITE", "Lax")
CSRF_COOKIE_SAMESITE = os.environ.get("CSRF_COOKIE_SAMESITE", "Lax")

# HTTP Strict Transport Security (enable only when serving HTTPS)
SECURE_HSTS_SECONDS = int(os.environ.get("SECURE_HSTS_SECONDS", "31536000")) if not DEBUG else 0
SECURE_HSTS_INCLUDE_SUBDOMAINS = (
    os.environ.get("SECURE_HSTS_INCLUDE_SUBDOMAINS", "True").lower() in ("1", "true", "yes")
    if not DEBUG
    else False
)
SECURE_HSTS_PRELOAD = (
    os.environ.get("SECURE_HSTS_PRELOAD", "True").lower() in ("1", "true", "yes")
    if not DEBUG
    else False
)

# Misc security headers
SECURE_REFERRER_POLICY = os.environ.get("SECURE_REFERRER_POLICY", "strict-origin-when-cross-origin")
SECURE_CONTENT_TYPE_NOSNIFF = True
X_FRAME_OPTIONS = "DENY"
