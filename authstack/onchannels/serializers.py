from rest_framework import serializers
from .models import Channel, Playlist, Video


class ChannelSerializer(serializers.ModelSerializer):
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
        ]
        read_only_fields = ("uid", "created_at", "updated_at")


class PlaylistSerializer(serializers.ModelSerializer):
    channel = serializers.SlugRelatedField(slug_field="id_slug", read_only=True)

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
        ]
        read_only_fields = ("last_synced_at",)


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
