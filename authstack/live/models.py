from django.db import models
from django.utils.translation import gettext_lazy as _
from onchannels.models import Channel


class Live(models.Model):
    class PlaybackType(models.TextChoices):
        HLS = "hls", "HLS (.m3u8)"
        DASH = "dash", "MPEG-DASH (.mpd)"

    # Link to existing onchannels.Channel
    channel = models.OneToOneField(Channel, on_delete=models.CASCADE, related_name="live")
    tenant = models.CharField(max_length=64, db_index=True, help_text="Tenant slug (e.g., ontime)")

    # Display
    title = models.CharField(max_length=255, blank=True, default="")
    description = models.TextField(blank=True, default="")
    poster_url = models.URLField(blank=True, default="")

    # Playback
    playback_url = models.CharField(max_length=1024, help_text="HLS/DASH URL")
    playback_type = models.CharField(max_length=8, choices=PlaybackType.choices, default=PlaybackType.HLS)
    drm = models.JSONField(default=dict, blank=True, help_text="Optional DRM config: {widevine: {license_url: ...}, fairplay: {...}}")

    # Flags
    is_active = models.BooleanField(default=True)
    is_previewable = models.BooleanField(default=True, help_text="Allow admin preview in Django")
    tags = models.JSONField(default=list, blank=True)
    meta = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at", "channel__sort_order"]
        verbose_name = _("Live")
        verbose_name_plural = _("Live")

    def __str__(self) -> str:  # pragma: no cover
        name = getattr(self.channel, "name_en", None) or getattr(self.channel, "name_am", None) or getattr(self.channel, "id_slug", "")
        return f"Live: {name}"


class LiveSchedule(models.Model):
    live = models.ForeignKey(Live, on_delete=models.CASCADE, related_name="schedules")
    title = models.CharField(max_length=255, blank=True, default="")
    description = models.TextField(blank=True, default="")
    start_at = models.DateTimeField()
    end_at = models.DateTimeField()
    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["start_at"]
        verbose_name = _("Live schedule")
        verbose_name_plural = _("Live schedules")

    def __str__(self) -> str:  # pragma: no cover
        return f"{self.title or 'Schedule'} ({self.start_at} - {self.end_at})"
