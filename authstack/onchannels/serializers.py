from rest_framework import serializers
from .models import Channel, Playlist, Video, ShortJob


class ChannelSerializer(serializers.ModelSerializer):
    logo_url = serializers.SerializerMethodField()
    # Expose helpful aliases expected by clients
    resolved_channel_id = serializers.SerializerMethodField()
    handle = serializers.SerializerMethodField()
    class Meta:
        model = Channel
        fields = [
            "uid",
            "tenant",
            "id_slug",
            "default_locale",
            "name_am",
            "name_en",
            "aliases",
            # YouTube linkage
            "youtube_handle",
            "youtube_channel_id",
            # Aliases for convenience
            "handle",
            "resolved_channel_id",
            "images",
            "sources",
            "genres",
            "language",
            "country",
            "tags",
            "is_active",
            "platforms",
            "drm_required",
            "sort_order",
            "featured",
            "rights",
            "audit",
            "created_at",
            "updated_at",
            "logo_url",
        ]
        read_only_fields = ("uid", "created_at", "updated_at")

    def get_logo_url(self, obj: Channel) -> str:
        # Prefer absolute when request provided; else relative path
        path = f"/api/channels/{obj.id_slug}/logo/"
        req = self.context.get("request") if hasattr(self, "context") else None
        return req.build_absolute_uri(path) if req else path

    def get_resolved_channel_id(self, obj: Channel) -> str | None:
        # Alias to youtube_channel_id for clearer meaning in some UIs
        return obj.youtube_channel_id

    def get_handle(self, obj: Channel) -> str | None:
        # Alias to youtube_handle (e.g., @ebstvWorldwide)
        return obj.youtube_handle


class PlaylistSerializer(serializers.ModelSerializer):
    channel = serializers.SlugRelatedField(slug_field="id_slug", read_only=True)
    channel_logo_url = serializers.SerializerMethodField()

    class Meta:
        model = Playlist
        fields = [
            "id",
            "channel",
            "title",
            "thumbnails",
            "item_count",
            "is_active",
            "last_synced_at",
            "channel_logo_url",
        ]
        read_only_fields = ("last_synced_at",)


class ShortJobSerializer(serializers.ModelSerializer):
    class Meta:
        model = ShortJob
        fields = [
            'id', 'tenant', 'requested_by', 'source_url', 'status', 'error_message', 'retry_count',
            'artifact_prefix', 'ladder_profile', 'duration_seconds', 'reserved_bytes', 'used_bytes',
            'hls_master_url', 'content_class', 'created_at', 'updated_at'
        ]
        read_only_fields = (
            'id', 'tenant', 'requested_by', 'status', 'error_message', 'retry_count',
            'artifact_prefix', 'duration_seconds', 'reserved_bytes', 'used_bytes',
            'hls_master_url', 'created_at', 'updated_at'
        )


class CreateShortJobSerializer(serializers.Serializer):
    source_url = serializers.CharField()
    ladder_profile = serializers.ChoiceField(choices=[('shorts_v1', 'shorts_v1'), ('shorts_premium', 'shorts_premium')], required=False, default='shorts_v1')
    content_class = serializers.ChoiceField(choices=[
        (ShortJob.CLASS_NORMAL, 'normal'),
        (ShortJob.CLASS_PREFERRED, 'preferred'),
        (ShortJob.CLASS_PINNED, 'pinned'),
        (ShortJob.CLASS_EPHEMERAL, 'ephemeral'),
    ], required=False, default=ShortJob.CLASS_NORMAL)

    def get_channel_logo_url(self, obj: Playlist) -> str:
        path = f"/api/channels/{obj.channel.id_slug}/logo/"
        req = self.context.get("request") if hasattr(self, "context") else None
        return req.build_absolute_uri(path) if req else path


class VideoSerializer(serializers.ModelSerializer):
    channel = serializers.SlugRelatedField(slug_field="id_slug", read_only=True)
    playlist = serializers.SlugRelatedField(slug_field="id", read_only=True)

    class Meta:
        model = Video
        fields = [
            "id",
            "channel",
            "playlist",
            "video_id",
            "title",
            "thumbnails",
            "position",
            "published_at",
            "is_active",
            "last_synced_at",
        ]
        read_only_fields = ("last_synced_at",)
