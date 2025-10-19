from rest_framework import serializers
from .models import Live, LiveSchedule


class LiveSerializer(serializers.ModelSerializer):
    channel_slug = serializers.SerializerMethodField()
    channel_name = serializers.SerializerMethodField()
    channel_logo_url = serializers.SerializerMethodField()

    class Meta:
        model = Live
        fields = [
            "id",
            "tenant",
            "channel",
            "channel_slug",
            "channel_name",
            "channel_logo_url",
            "title",
            "description",
            "poster_url",
            "playback_url",
            "playback_type",
            "drm",
            "is_active",
            "is_previewable",
            "tags",
            "meta",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ("created_at", "updated_at")

    def get_channel_slug(self, obj: Live) -> str:
        return getattr(obj.channel, "id_slug", "")

    def get_channel_name(self, obj: Live) -> str:
        return getattr(obj.channel, "name_en", None) or getattr(obj.channel, "name_am", None) or getattr(obj.channel, "id_slug", "")

    def get_channel_logo_url(self, obj: Live) -> str:
        slug = getattr(obj.channel, "id_slug", "")
        path = f"/api/channels/{slug}/logo/"
        req = self.context.get("request") if hasattr(self, "context") else None
        return req.build_absolute_uri(path) if req else path


class LiveScheduleSerializer(serializers.ModelSerializer):
    class Meta:
        model = LiveSchedule
        fields = [
            "id",
            "live",
            "title",
            "description",
            "start_at",
            "end_at",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ("created_at", "updated_at")
