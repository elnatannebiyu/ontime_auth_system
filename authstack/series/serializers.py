from rest_framework import serializers
from .models import Show, Season, Episode


class ShowSerializer(serializers.ModelSerializer):
    cover_image = serializers.SerializerMethodField()

    class Meta:
        model = Show
        fields = [
            "id",
            "tenant",
            "slug",
            "title",
            "synopsis",
            "cover_image",
            "default_locale",
            "tags",
            "channel",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ("created_at", "updated_at")

    def get_cover_image(self, obj: Show) -> str | None:
        # Prefer explicit Show cover if set
        if getattr(obj, "cover_image", None):
            val = (obj.cover_image or "").strip()
            if val:
                return self._abs_url(val)
        # Fallback to the latest enabled Season cover
        try:
            season = (
                Season.objects.filter(show=obj, is_enabled=True)
                .exclude(cover_image__isnull=True)
                .exclude(cover_image="")
                .order_by("-number")
                .first()
            )
            if season and season.cover_image:
                return self._abs_url(season.cover_image)
        except Exception:
            pass
        return None

    def _abs_url(self, url: str) -> str:
        if not url:
            return url
        # If already absolute (http/https), return as-is
        if url.startswith("http://") or url.startswith("https://"):
            return url
        # Otherwise, build absolute using request
        request = self.context.get("request") if hasattr(self, "context") else None
        if request is not None:
            try:
                return request.build_absolute_uri(url)
            except Exception:
                return url
        return url


class SeasonSerializer(serializers.ModelSerializer):
    show = serializers.SlugRelatedField(slug_field="slug", read_only=True)
    cover_image = serializers.SerializerMethodField()

    class Meta:
        model = Season
        fields = [
            "id",
            "tenant",
            "show",
            "number",
            "title",
            "cover_image",
            "is_enabled",
            "yt_playlist_id",
            "include_rules",
            "exclude_rules",
            "last_synced_at",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ("last_synced_at", "created_at", "updated_at")

    def get_cover_image(self, obj: Season) -> str | None:
        val = (obj.cover_image or "").strip() if getattr(obj, "cover_image", None) else ""
        if not val:
            return None
        # Use same helper as ShowSerializer to absolutize
        request = self.context.get("request") if hasattr(self, "context") else None
        if val.startswith("http://") or val.startswith("https://"):
            return val
        if request is not None:
            try:
                return request.build_absolute_uri(val)
            except Exception:
                return val
        return val


class EpisodeSerializer(serializers.ModelSerializer):
    season = serializers.PrimaryKeyRelatedField(read_only=True)
    display_title = serializers.SerializerMethodField()

    class Meta:
        model = Episode
        fields = [
            "id",
            "tenant",
            "season",
            "source_video_id",
            "source_published_at",
            "episode_number",
            "title",
            "description",
            "duration_seconds",
            "thumbnails",
            "title_override",
            "description_override",
            "publish_at",
            "visible",
            "status",
            "display_title",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ("created_at", "updated_at")

    def get_display_title(self, obj: Episode) -> str:
        return obj.display_title
