from django.db import models
import uuid


class Channel(models.Model):
    uid = models.UUIDField(default=uuid.uuid4, editable=False, unique=True)
    tenant = models.CharField(max_length=64, default="ontime", db_index=True)
    # Slug identifier (e.g., abbay-tv)
    id_slug = models.SlugField(max_length=128, unique=True)

    # Localization
    default_locale = models.CharField(max_length=8, choices=[("am", "Amharic"), ("en", "English")], default="am")
    name_am = models.CharField(max_length=255, blank=True, null=True)
    name_en = models.CharField(max_length=255, blank=True, null=True)
    aliases = models.JSONField(default=list, blank=True)  # [{locale,value}]

    # YouTube linkage
    youtube_handle = models.CharField(max_length=128, blank=True, null=True, help_text="Channel handle like @ebstvWorldwide")
    youtube_channel_id = models.CharField(max_length=64, blank=True, null=True, help_text="Resolved UC... channel ID")

    # Images and sources stored as JSON for now for speed of integration
    images = models.JSONField(default=list, blank=True)   # [{kind, path|url, ...}]
    sources = models.JSONField(default=list, blank=True)  # [{type, status, ...}]

    # Categorization
    genres = models.JSONField(default=list, blank=True)
    language = models.CharField(max_length=8, default="am")
    country = models.CharField(max_length=2, default="ET")
    tags = models.JSONField(default=list, blank=True)

    # Availability
    is_active = models.BooleanField(default=True)
    platforms = models.JSONField(default=list, blank=True)  # ["mobile","web","tv"]
    drm_required = models.BooleanField(default=False)

    # Lineup
    sort_order = models.IntegerField(default=100)
    featured = models.BooleanField(default=False)

    # Optional blobs
    rights = models.JSONField(default=dict, blank=True)
    audit = models.JSONField(default=dict, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["sort_order", "id_slug"]
        verbose_name = "Channel"
        verbose_name_plural = "Channels"

    def __str__(self) -> str:
        return self.name_en or self.name_am or self.id_slug


class Playlist(models.Model):
    """YouTube playlist pulled for a Channel."""
    id = models.CharField(primary_key=True, max_length=64)  # YouTube playlist ID (PL...)
    channel = models.ForeignKey(Channel, on_delete=models.CASCADE, related_name="playlists")
    title = models.CharField(max_length=255)
    thumbnails = models.JSONField(default=dict, blank=True)
    item_count = models.IntegerField(default=0)
    is_active = models.BooleanField(default=False, help_text="Mark playlists active to surface in apps")
    last_synced_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["channel", "title"]
        verbose_name = "Playlist"
        verbose_name_plural = "Playlists"

    def __str__(self) -> str:
        return f"{self.title} ({self.id})"


class Video(models.Model):
    """Video item belonging to a specific Playlist (and Channel)."""
    channel = models.ForeignKey(Channel, on_delete=models.CASCADE, related_name="videos")
    playlist = models.ForeignKey(Playlist, on_delete=models.CASCADE, related_name="videos")
    video_id = models.CharField(max_length=32, db_index=True)
    title = models.CharField(max_length=255, blank=True, default="")
    thumbnails = models.JSONField(default=dict, blank=True)
    position = models.IntegerField(blank=True, null=True)
    published_at = models.DateTimeField(blank=True, null=True)
    is_active = models.BooleanField(default=True)
    last_synced_at = models.DateTimeField(auto_now=True)

    class Meta:
        ordering = ["playlist", "position", "video_id"]
        unique_together = (("playlist", "video_id"),)
        verbose_name = "Video"
        verbose_name_plural = "Videos"

    def __str__(self) -> str:
        return f"{self.title or self.video_id}"
