from django.db import models
import uuid
from django.utils import timezone
from django.contrib.auth import get_user_model


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
    is_shorts = models.BooleanField(default=False, db_index=True, help_text="Mark playlist as part of Shorts feed")
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


# Scheduled Notification model (lives here to be auto-discovered by Django)
User = get_user_model()


class ScheduledNotification(models.Model):
    TARGET_TOKEN = 'token'
    TARGET_TOPIC = 'topic'
    TARGET_USER = 'user'

    STATUS_PENDING = 'pending'
    STATUS_SENT = 'sent'
    STATUS_FAILED = 'failed'

    TARGET_CHOICES = [
        (TARGET_TOKEN, 'Token'),
        (TARGET_TOPIC, 'Topic'),
        (TARGET_USER, 'User'),
    ]

    STATUS_CHOICES = [
        (STATUS_PENDING, 'Pending'),
        (STATUS_SENT, 'Sent'),
        (STATUS_FAILED, 'Failed'),
    ]

    title = models.CharField(max_length=200)
    body = models.TextField()
    data = models.JSONField(blank=True, null=True)

    target_type = models.CharField(max_length=10, choices=TARGET_CHOICES, default=TARGET_TOKEN)
    target_value = models.TextField(blank=True)
    target_user = models.ForeignKey(User, null=True, blank=True, on_delete=models.SET_NULL, related_name='scheduled_notifications')

    send_at = models.DateTimeField(help_text='UTC time to send')
    status = models.CharField(max_length=10, choices=STATUS_CHOICES, default=STATUS_PENDING)
    attempts = models.PositiveIntegerField(default=0)
    last_error = models.TextField(blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['status', 'send_at']),
            models.Index(fields=['target_type']),
        ]
        ordering = ['send_at']

    def is_due(self) -> bool:
        return self.status == self.STATUS_PENDING and self.send_at <= timezone.now()


class UserNotification(models.Model):
    user = models.ForeignKey(User, on_delete=models.CASCADE, related_name='notifications', db_index=True)
    tenant = models.CharField(max_length=64, default='ontime', db_index=True)
    title = models.CharField(max_length=200)
    body = models.TextField(blank=True, default='')
    data = models.JSONField(blank=True, null=True)
    read_at = models.DateTimeField(blank=True, null=True)
    created_at = models.DateTimeField(auto_now_add=True)

    class Meta:
        indexes = [
            models.Index(fields=['user', '-created_at']),
            models.Index(fields=['user', 'read_at']),
        ]
        ordering = ['-created_at']
        verbose_name = 'User Notification'
        verbose_name_plural = 'User Notifications'

    def mark_read(self):
        if not self.read_at:
            self.read_at = timezone.now()
            self.save(update_fields=['read_at'])


# Shorts ingestion job model
class ShortJob(models.Model):
    STATUS_QUEUED = 'queued'
    STATUS_DOWNLOADING = 'downloading'
    STATUS_TRANSCODING = 'transcoding'
    STATUS_UPLOADING = 'uploading'
    STATUS_READY = 'ready'
    STATUS_RETIRING = 'retiring'
    STATUS_DELETED = 'deleted'
    STATUS_FAILED = 'failed'

    CLASS_PINNED = 'pinned'
    CLASS_PREFERRED = 'preferred'
    CLASS_NORMAL = 'normal'
    CLASS_EPHEMERAL = 'ephemeral'

    STATUS_CHOICES = [
        (STATUS_QUEUED, 'Queued'),
        (STATUS_DOWNLOADING, 'Downloading'),
        (STATUS_TRANSCODING, 'Transcoding'),
        (STATUS_UPLOADING, 'Uploading'),
        (STATUS_READY, 'Ready'),
        (STATUS_RETIRING, 'Retiring'),
        (STATUS_DELETED, 'Deleted'),
        (STATUS_FAILED, 'Failed'),
    ]

    CLASS_CHOICES = [
        (CLASS_PINNED, 'Pinned'),
        (CLASS_PREFERRED, 'Preferred'),
        (CLASS_NORMAL, 'Normal'),
        (CLASS_EPHEMERAL, 'Ephemeral'),
    ]

    id = models.UUIDField(primary_key=True, default=uuid.uuid4, editable=False)
    tenant = models.CharField(max_length=64, default='ontime', db_index=True)
    requested_by = models.ForeignKey(User, null=True, blank=True, on_delete=models.SET_NULL, related_name='short_jobs')
    source_url = models.TextField(help_text='Original source URL or video identifier')
    status = models.CharField(max_length=16, choices=STATUS_CHOICES, default=STATUS_QUEUED, db_index=True)
    error_message = models.TextField(blank=True, default='')
    retry_count = models.PositiveIntegerField(default=0)

    artifact_prefix = models.CharField(max_length=255, blank=True, default='')
    ladder_profile = models.CharField(max_length=64, default='shorts_v1')
    duration_seconds = models.PositiveIntegerField(default=0)

    reserved_bytes = models.BigIntegerField(default=0)
    used_bytes = models.BigIntegerField(default=0)

    hls_master_url = models.TextField(blank=True, default='')

    content_class = models.CharField(max_length=16, choices=CLASS_CHOICES, default=CLASS_NORMAL)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['tenant', 'status', '-created_at']),
        ]
        ordering = ['-created_at']
        verbose_name = 'Short Ingestion Job'
        verbose_name_plural = 'Short Ingestion Jobs'

    def __str__(self) -> str:
        return f"ShortJob {self.id} [{self.status}]"
