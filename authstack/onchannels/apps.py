from django.apps import AppConfig


class ChannelsConfig(AppConfig):
    default_auto_field = "django.db.models.BigAutoField"
    # Python package name
    name = "onchannels"
    # Django app label (kept as 'channels' for admin display/migrations)
    label = "channels"
    verbose_name = "Channels"
