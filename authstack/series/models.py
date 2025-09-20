from django.db import models
from django.utils import timezone
from django.conf import settings
from onchannels.models import Channel


class Show(models.Model):
    tenant = models.CharField(max_length=64, db_index=True, default="ontime")
    slug = models.SlugField(max_length=128, unique=True)
    title = models.CharField(max_length=255)
    synopsis = models.TextField(blank=True, default="")
    cover_image = models.URLField(blank=True, null=True)
    # Optional uploaded cover; when provided, admin will mirror its URL into cover_image
    cover_upload = models.ImageField(upload_to="series/covers/shows/", blank=True, null=True)
    default_locale = models.CharField(max_length=8, default="am")
    tags = models.JSONField(default=list, blank=True)
    channel = models.ForeignKey(Channel, on_delete=models.PROTECT, related_name="shows")
    is_active = models.BooleanField(default=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["title", "slug"]
        indexes = [
            models.Index(fields=["tenant", "slug"]),
            models.Index(fields=["tenant", "is_active"]),
        ]
        permissions = (
            ("manage_content", "Can manage series content"),
        )

    def __str__(self) -> str:
        return f"{self.title} ({self.slug})"


class Season(models.Model):
    tenant = models.CharField(max_length=64, db_index=True, default="ontime")
    show = models.ForeignKey(Show, on_delete=models.CASCADE, related_name="seasons")
    number = models.IntegerField()
    title = models.CharField(max_length=255, blank=True, default="")
    cover_image = models.URLField(blank=True, null=True)
    cover_upload = models.ImageField(upload_to="series/covers/seasons/", blank=True, null=True)
    is_enabled = models.BooleanField(default=True)

    # Mapping to YouTube
    yt_playlist_id = models.CharField(max_length=64, help_text="YouTube playlist ID (PL...)")
    include_rules = models.JSONField(default=list, blank=True)
    exclude_rules = models.JSONField(default=list, blank=True)

    last_synced_at = models.DateTimeField(blank=True, null=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["show", "number"]
        unique_together = (("show", "number"),)
        indexes = [
            models.Index(fields=["tenant", "show", "number"]),
            models.Index(fields=["tenant", "yt_playlist_id"]),
            models.Index(fields=["tenant", "is_enabled"]),
        ]

    def __str__(self) -> str:
        return f"{self.show.title} S{self.number}"


class Episode(models.Model):
    STATUS_PUBLISHED = "published"
    STATUS_DRAFT = "draft"
    STATUS_NEEDS_REVIEW = "needs_review"
    STATUS_CHOICES = [
        (STATUS_PUBLISHED, "Published"),
        (STATUS_DRAFT, "Draft"),
        (STATUS_NEEDS_REVIEW, "Needs Review"),
    ]

    tenant = models.CharField(max_length=64, db_index=True, default="ontime")
    season = models.ForeignKey(Season, on_delete=models.CASCADE, related_name="episodes")

    # Source mapping
    source_video_id = models.CharField(max_length=32, db_index=True)
    source_published_at = models.DateTimeField(blank=True, null=True)

    # Content
    episode_number = models.IntegerField(blank=True, null=True)
    title = models.CharField(max_length=255)
    description = models.TextField(blank=True, default="")
    duration_seconds = models.IntegerField(blank=True, null=True)
    thumbnails = models.JSONField(default=dict, blank=True)

    # Editorial overrides
    title_override = models.CharField(max_length=255, blank=True, default="")
    description_override = models.TextField(blank=True, default="")
    publish_at = models.DateTimeField(blank=True, null=True)

    # Visibility/state
    visible = models.BooleanField(default=True)
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_PUBLISHED)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["season", "episode_number", "source_published_at", "id"]
        indexes = [
            models.Index(fields=["tenant", "season", "episode_number"]),
            models.Index(fields=["tenant", "season", "source_video_id"]),
            models.Index(fields=["tenant", "status", "visible"]),
        ]
        unique_together = (("season", "source_video_id"),)

    def __str__(self) -> str:
        disp = self.title_override or self.title
        return f"{disp} (S{self.season.number}{'E'+str(self.episode_number) if self.episode_number else ''})"

    @property
    def display_title(self) -> str:
        return self.title_override or self.title


class EpisodeView(models.Model):
    """Lightweight analytics for episode playback."""
    tenant = models.CharField(max_length=64, db_index=True, default="ontime")
    episode = models.ForeignKey(Episode, on_delete=models.CASCADE, related_name="views")
    user = models.ForeignKey(settings.AUTH_USER_MODEL, on_delete=models.SET_NULL, null=True, blank=True)
    session_id = models.CharField(max_length=128, blank=True, default="")
    device_id = models.CharField(max_length=128, blank=True, default="")
    source_provider = models.CharField(max_length=32, default="youtube")
    playback_token = models.CharField(max_length=64, blank=True, default="")

    started_at = models.DateTimeField(default=timezone.now)
    last_heartbeat_at = models.DateTimeField(blank=True, null=True)
    total_seconds = models.IntegerField(default=0)
    completed = models.BooleanField(default=False)

    ip = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.TextField(blank=True, default="")

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=["tenant", "episode"]),
            models.Index(fields=["tenant", "started_at"]),
        ]

    def __str__(self) -> str:
        return f"View ep={self.episode_id} secs={self.total_seconds} completed={self.completed}"
