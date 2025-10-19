from django.apps import AppConfig


class LiveConfig(AppConfig):
    # Django import path
    name = "live"
    # Use default app label 'live' to avoid conflicts with 'onchannels'
    verbose_name = "Live"
