from rest_framework import serializers
from .models import Show, Season, Episode, Category


class CategoryMiniSerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = [
            "name",
            "slug",
            "color",
        ]


class CategoryListSerializer(serializers.ModelSerializer):
    class Meta:
        model = Category
        fields = [
            "name",
            "slug",
            "color",
            "description",
            "display_order",
            "is_active",
        ]


class ShowSerializer(serializers.ModelSerializer):
    cover_image = serializers.SerializerMethodField()
    channel_logo_url = serializers.SerializerMethodField()
    categories = CategoryMiniSerializer(many=True, read_only=True)
    category_slugs = serializers.ListField(
        child=serializers.SlugField(), write_only=True, required=False
    )

    class Meta:
        model = Show
        fields = [
            "id",
            "tenant",
            "slug",
            "title",
            "synopsis",
            "cover_image",
            "channel_logo_url",
            "default_locale",
            "tags",
            "channel",
            "categories",
            "category_slugs",
            "is_active",
            "created_at",
            "updated_at",
        ]
        read_only_fields = ("created_at", "updated_at")

    def _set_categories(self, show: Show, slugs: list[str]):
        if slugs is None:
            return
        request = getattr(self, "context", {}).get("request") if hasattr(self, "context") else None
        tenant = getattr(request, "tenant", None) if request is not None else None
        qs = Category.objects.all()
        if tenant is not None:
            qs = qs.filter(tenant=getattr(tenant, "slug", tenant))
        cats = list(qs.filter(slug__in=slugs)) if slugs else []
        show.categories.set(cats)

    def create(self, validated_data):
        slugs = validated_data.pop("category_slugs", [])
        show = super().create(validated_data)
        self._set_categories(show, slugs)
        return show

    def update(self, instance, validated_data):
        slugs = validated_data.pop("category_slugs", None)
        show = super().update(instance, validated_data)
        if slugs is not None:
            self._set_categories(show, slugs)
        return show

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
        # Fallback to latest episode thumbnail (best available size)
        try:
            from .models import Episode  # local import to avoid circulars in some contexts
            ep = (
                Episode.objects.filter(season__show=obj, visible=True, status=Episode.STATUS_PUBLISHED)
                .order_by("-source_published_at", "-id")
                .first()
            )
            if ep and getattr(ep, "thumbnails", None):
                thumbs = ep.thumbnails or {}
                if isinstance(thumbs, dict):
                    for k in ["maxres", "standard", "high", "medium", "default"]:
                        t = thumbs.get(k) or {}
                        url = t.get("url") if isinstance(t, dict) else None
                        if url:
                            return self._abs_url(url)
                    # direct url key if present
                    url = thumbs.get("url")
                    if isinstance(url, str) and url:
                        return self._abs_url(url)
        except Exception:
            pass
        # Fallback to onchannels.Video by Season.yt_playlist_id (when Episodes are not yet materialized)
        try:
            # Find the most recent enabled season having a YouTube playlist id
            season2 = (
                Season.objects.filter(show=obj, is_enabled=True)
                .exclude(yt_playlist_id__isnull=True)
                .exclude(yt_playlist_id="")
                .order_by("-number")
                .first()
            )
            if season2 and season2.yt_playlist_id:
                from onchannels.models import Video as OCVideo  # type: ignore
                v = (
                    OCVideo.objects.filter(playlist_id=season2.yt_playlist_id)
                    .order_by("-published_at", "-last_synced_at")
                    .first()
                )
                if v and getattr(v, "thumbnails", None):
                    tmap = v.thumbnails or {}
                    if isinstance(tmap, dict):
                        for k in ["maxres", "standard", "high", "medium", "default"]:
                            t = tmap.get(k) or {}
                            url = t.get("url") if isinstance(t, dict) else None
                            if url:
                                return self._abs_url(url)
                        url = tmap.get("url")
                        if isinstance(url, str) and url:
                            return self._abs_url(url)
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

    def get_channel_logo_url(self, obj: Show) -> str:
        try:
            ch = getattr(obj, 'channel', None)
            slug = getattr(ch, 'id_slug', None)
            if not slug:
                return ""
            path = f"/api/channels/{slug}/logo/"
            request = self.context.get("request") if hasattr(self, "context") else None
            return request.build_absolute_uri(path) if request is not None else path
        except Exception:
            return ""


class SeasonSerializer(serializers.ModelSerializer):
    show = serializers.SlugRelatedField(slug_field="slug", queryset=Show.objects.all())
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
    season = serializers.PrimaryKeyRelatedField(queryset=Season.objects.all())
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
