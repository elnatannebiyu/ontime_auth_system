# Production settings
# Usage: set environment variable DJANGO_SETTINGS_MODULE=authstack.settings_prod

from .settings import *  # noqa
import os
from pathlib import Path

# --- Core ---
DEBUG = False
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY")
if not SECRET_KEY:
    raise RuntimeError("DJANGO_SECRET_KEY must be set in production")

ALLOWED_HOSTS = [h for h in os.environ.get("ALLOWED_HOSTS", "").split(",") if h.strip()] or ["localhost"]

# --- Security & HTTPS ---
SECURE_SSL_REDIRECT = os.environ.get("SECURE_SSL_REDIRECT", "True") == "True"
SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")
SESSION_COOKIE_SECURE = os.environ.get("SESSION_COOKIE_SECURE", "True") == "True"
CSRF_COOKIE_SECURE = os.environ.get("CSRF_COOKIE_SECURE", "True") == "True"
SESSION_COOKIE_SAMESITE = "Lax"  # or "None" if you need cross-site cookies with HTTPS
CSRF_COOKIE_SAMESITE = "Lax"
SECURE_HSTS_SECONDS = int(os.environ.get("SECURE_HSTS_SECONDS", "31536000"))
SECURE_HSTS_INCLUDE_SUBDOMAINS = True
SECURE_HSTS_PRELOAD = True
SECURE_REFERRER_POLICY = "strict-origin-when-cross-origin"

# --- Database ---
# Prefer DATABASE_URL if provided; fallback to sqlite (not recommended for prod)
DATABASE_URL = os.environ.get("DATABASE_URL", "")
if DATABASE_URL:
    import dj_database_url  # type: ignore
    DATABASES["default"] = dj_database_url.parse(DATABASE_URL, conn_max_age=600)
else:
    # Keep sqlite as last resort
    BASE_DIR = Path(__file__).resolve().parent.parent
    DATABASES = {
        "default": {
            "ENGINE": "django.db.backends.sqlite3",
            "NAME": BASE_DIR / "db.sqlite3",
        }
    }

# --- Caches ---
# Use Redis if REDIS_URL is provided; else LocMem
REDIS_URL = os.environ.get("REDIS_URL", "")
if REDIS_URL:
    CACHES = {
        "default": {
            "BACKEND": "django_redis.cache.RedisCache",
            "LOCATION": REDIS_URL,
            "OPTIONS": {"CLIENT_CLASS": "django_redis.client.DefaultClient"},
        }
    }
else:
    CACHES = {
        'default': {
            'BACKEND': 'django.core.cache.backends.locmem.LocMemCache',
            'LOCATION': 'prod-locmem',
        }
    }

# --- CORS / CSRF ---
_frontend = [u for u in os.environ.get("FRONTEND_ORIGINS", "").split(",") if u.strip()]
if _frontend:
    CORS_ALLOWED_ORIGINS = _frontend
    CSRF_TRUSTED_ORIGINS = _frontend
CORS_ALLOW_CREDENTIALS = True

# --- SimpleJWT / refresh cookie ---
# Keep lifetimes; ensure cookie path aligns with logout and refresh endpoints
REFRESH_COOKIE_NAME = os.environ.get("REFRESH_COOKIE_NAME", "refresh_token")
REFRESH_COOKIE_PATH = os.environ.get("REFRESH_COOKIE_PATH", "/")

# --- Static files ---
STATIC_ROOT = os.environ.get("STATIC_ROOT", str(Path(BASE_DIR) / "staticfiles"))
STATIC_URL = STATIC_URL  # from base settings

# WhiteNoise: serve static files via Gunicorn (compressed + hashed filenames)
MIDDLEWARE.insert(1, 'whitenoise.middleware.WhiteNoiseMiddleware')
STATICFILES_STORAGE = 'whitenoise.storage.CompressedManifestStaticFilesStorage'

# --- Swagger / drf_yasg ---
# Do not expose Swagger UI in production unless explicitly allowed
if os.environ.get("ENABLE_SWAGGER", "False") != "True":
    INSTALLED_APPS = [app for app in INSTALLED_APPS if app != 'drf_yasg']

# --- Email backend ---
if os.environ.get('EMAIL_BACKEND'):
    EMAIL_BACKEND = os.environ['EMAIL_BACKEND']

# --- Logging ---
LOGGING = {
    "version": 1,
    "disable_existing_loggers": False,
    "handlers": {
        "console": {"class": "logging.StreamHandler"},
    },
    "root": {"handlers": ["console"], "level": os.environ.get("LOG_LEVEL", "INFO")},
}
