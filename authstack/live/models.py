from django.db import models
from django.utils.translation import gettext_lazy as _
from django.conf import settings
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
    language = models.CharField(max_length=32, blank=True, default="")
    country = models.CharField(max_length=64, blank=True, default="")
    city = models.CharField(max_length=64, blank=True, default="")
    category = models.CharField(max_length=64, blank=True, default="")
    is_local = models.BooleanField(default=False)

    # Playback
    playback_url = models.CharField(max_length=1024, help_text="HLS/DASH URL")
    playback_type = models.CharField(max_length=8, choices=PlaybackType.choices, default=PlaybackType.HLS)
    drm = models.JSONField(default=dict, blank=True, help_text="Optional DRM config: {widevine: {license_url: ...}, fairplay: {...}}")
    # Extended streaming info
    stream_url = models.CharField(max_length=1024, blank=True, default="", help_text="Main live stream URL (alias of playback_url)")
    backup_stream_url = models.CharField(max_length=1024, blank=True, default="")
    stream_type = models.CharField(max_length=32, blank=True, default="", help_text="HLS, DASH, RTMP, YouTube Live, IPTV, etc.")
    bitrate = models.IntegerField(null=True, blank=True, help_text="kbps")
    resolution = models.CharField(max_length=16, blank=True, default="", help_text="e.g., 720p, 1080p")
    aspect_ratio = models.CharField(max_length=16, blank=True, default="", help_text="e.g., 16:9")
    is_verified = models.BooleanField(default=False)
    requires_vpn = models.BooleanField(default=False)

    # Flags
    is_active = models.BooleanField(default=True)
    is_previewable = models.BooleanField(default=True, help_text="Allow admin preview in Django")
    tags = models.JSONField(default=list, blank=True)
    meta = models.JSONField(default=dict, blank=True)

    # Display / Branding
    logo = models.URLField(blank=True, default="")
    banner_image = models.URLField(blank=True, default="")
    thumbnail_url = models.URLField(blank=True, default="")
    website_url = models.URLField(blank=True, default="")
    facebook_url = models.URLField(blank=True, default="")
    twitter_url = models.URLField(blank=True, default="")
    instagram_url = models.URLField(blank=True, default="")
    youtube_url = models.URLField(blank=True, default="")

    # Access & Monetization
    is_free = models.BooleanField(default=True)
    requires_login = models.BooleanField(default=False)
    price_per_month = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    payment_provider = models.CharField(max_length=32, blank=True, default="", help_text="Chapa, Telebirr, Stripe, etc.")
    access_token_expiry = models.DateTimeField(null=True, blank=True)
    region_lock = models.JSONField(default=list, blank=True, help_text="List of allowed countries or codes")
    license_expiry_date = models.DateField(null=True, blank=True)
    ad_enabled = models.BooleanField(default=False)

    # Scheduling & Content
    has_epg = models.BooleanField(default=False)
    epg_url = models.URLField(blank=True, default="")
    schedule_updated_at = models.DateTimeField(null=True, blank=True)
    current_program = models.CharField(max_length=255, blank=True, default="")
    next_program = models.CharField(max_length=255, blank=True, default="")

    # Analytics / Admin
    viewer_count = models.IntegerField(default=0, help_text="Current live viewers")
    total_views = models.BigIntegerField(default=0, help_text="Cumulative view count")
    stream_health = models.CharField(max_length=64, blank=True, default="")
    priority = models.IntegerField(default=100)
    # audio analytics kept for parity in TV model if needed
    listener_count = models.IntegerField(default=0, help_text="Current or last known listeners (if applicable)")
    total_listens = models.BigIntegerField(default=0, help_text="Total play count (if applicable)")
    added_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="live_added",
        help_text="Which admin or user created the entry",
    )

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


class LiveRadio(models.Model):
    # Optional linkage to Channel
    channel = models.OneToOneField(Channel, on_delete=models.SET_NULL, null=True, blank=True, related_name="radio")
    tenant = models.CharField(max_length=64, db_index=True, help_text="Tenant slug (e.g., ontime)")

    # Basic Info
    name = models.CharField(max_length=255)
    slug = models.SlugField(max_length=128, unique=True)
    description = models.TextField(blank=True, default="")
    language = models.CharField(max_length=32, blank=True, default="")
    country = models.CharField(max_length=64, blank=True, default="")
    city = models.CharField(max_length=64, blank=True, default="")
    category = models.CharField(max_length=64, blank=True, default="")

    # Streaming Info
    stream_url = models.CharField(max_length=1024)
    backup_stream_url = models.CharField(max_length=1024, blank=True, default="")
    bitrate = models.IntegerField(null=True, blank=True)
    format = models.CharField(max_length=32, blank=True, default="", help_text="HLS, AAC, MP3, RTMP, etc.")
    is_active = models.BooleanField(default=True)
    is_verified = models.BooleanField(default=False)

    # Display / Media
    logo = models.URLField(blank=True, default="")
    banner_image = models.URLField(blank=True, default="")
    website_url = models.URLField(blank=True, default="")
    facebook_url = models.URLField(blank=True, default="")
    twitter_url = models.URLField(blank=True, default="")
    instagram_url = models.URLField(blank=True, default="")

    # Access Control
    is_free = models.BooleanField(default=True)
    price_per_month = models.DecimalField(max_digits=8, decimal_places=2, null=True, blank=True)
    requires_login = models.BooleanField(default=False)
    payment_provider = models.CharField(max_length=32, blank=True, default="")
    access_token_expiry = models.DateTimeField(null=True, blank=True)

    # Analytics / Admin
    listener_count = models.IntegerField(default=0, help_text="Current or last known listeners")
    total_listens = models.BigIntegerField(default=0, help_text="Total play count")
    priority = models.IntegerField(default=100)
    added_by = models.ForeignKey(
        settings.AUTH_USER_MODEL,
        null=True,
        blank=True,
        on_delete=models.SET_NULL,
        related_name="radio_added",
        help_text="Which admin or user created the entry",
    )

    # Diagnostics / Health
    last_check_ok = models.BooleanField(default=False, help_text="Whether the last health check succeeded")
    last_check_at = models.DateTimeField(null=True, blank=True)
    last_error = models.CharField(max_length=255, blank=True, default="")

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["-updated_at", "priority", "name"]
        verbose_name = _("Live radio")
        verbose_name_plural = _("Live radios")

    def __str__(self) -> str:  # pragma: no cover
        return f"Radio: {self.name}"
