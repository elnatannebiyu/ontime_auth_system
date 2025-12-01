from django.contrib import admin
from django import forms
from django.utils.text import slugify
from django.http import JsonResponse
from django.urls import path
from django.db.models import Count
from .models import Show, Season, Episode, Category
from onchannels.models import Channel, Playlist


class ShowAdminForm(forms.ModelForm):
    class Meta:
        model = Show
        fields = "__all__"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Determine tenant from form data or instance
        tenant_val = None
        if hasattr(self, "data") and self.data:
            tenant_val = self.data.get("tenant")
        if not tenant_val and getattr(self.instance, "tenant", None):
            tenant_val = self.instance.tenant
        # Filter channel choices: active channels for the same tenant if provided
        if "channel" in self.fields:
            qs = Channel.objects.filter(is_active=True)
            if tenant_val:
                qs = qs.filter(tenant=tenant_val)
            self.fields["channel"].queryset = qs


@admin.register(Show)
class ShowAdmin(admin.ModelAdmin):
    form = ShowAdminForm
    list_display = ("title", "slug", "tenant", "channel", "is_active")
    list_filter = ("tenant", "is_active", "channel", "categories")
    search_fields = ("title", "slug")
    # Keep title-based prepopulation as a hint; we will also enforce channel-based default in save_model
    prepopulated_fields = {"slug": ("title",)}
    filter_horizontal = ("categories",)

    fieldsets = (
        (None, {
            'fields': ("tenant", "channel", "title", "slug", "synopsis", "is_active")
        }),
        ("Cover", {
            'fields': ("cover_upload", "cover_image"),
            'description': "Upload a cover image or paste a URL. If both are set, the uploaded file URL will be used.",
        }),
        ("Metadata", {
            'fields': ("default_locale", "tags", "categories"),
        }),
    )

    def save_model(self, request, obj: Show, form, change):
        # If slug is empty, auto-suggest from channel.id_slug (or title as fallback)
        if not obj.slug:
            base = None
            if obj.channel_id:
                try:
                    ch = Channel.objects.get(pk=obj.channel_id)
                    base = ch.id_slug
                except Channel.DoesNotExist:
                    base = None
            if not base:
                base = slugify(obj.title or "show")
            slug_candidate = base
            # Ensure uniqueness within Show.slug
            i = 1
            while Show.objects.filter(slug=slug_candidate).exclude(pk=getattr(obj, "pk", None)).exists():
                slug_candidate = f"{base}-show" if i == 1 else f"{base}-show-{i}"
                i += 1
            obj.slug = slug_candidate
        # If title is blank, default from channel name
        if not (obj.title or "").strip() and obj.channel_id:
            try:
                ch = Channel.objects.get(pk=obj.channel_id)
                obj.title = ch.name_en or ch.name_am or ch.id_slug
            except Channel.DoesNotExist:
                pass
        # If an upload is provided, mirror its URL into cover_image
        try:
            if getattr(obj, "cover_upload", None):
                f = obj.cover_upload
                if f and hasattr(f, "url"):
                    obj.cover_image = f.url
        except Exception:
            pass
        super().save_model(request, obj, form, change)

    # Provide a small JSON API for offering playlist titles for the selected channel
    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path("fetch_channel_playlists/", self.admin_site.admin_view(self.fetch_channel_playlists_view), name="series_show_fetch_channel_playlists"),
        ]
        return custom + urls

    def fetch_channel_playlists_view(self, request):
        """Return JSON list of active playlists for a given channel id.

        Query params: channel_id=<pk>
        Response: {"results": [{"id": "PL...", "title": "..."}, ...]}
        """
        channel_id = request.GET.get("channel_id")
        results = []
        if channel_id:
            pls = Playlist.objects.filter(channel_id=channel_id, is_active=True).order_by("title")
            results = [{"id": pl.id, "title": pl.title} for pl in pls]
        return JsonResponse({"results": results})

    class Media:
        js = ("series/show_admin.js",)


class EpisodeInline(admin.TabularInline):
    model = Episode
    extra = 0
    fields = ("episode_number", "title", "visible", "status", "updated_at")
    readonly_fields = ("updated_at",)


class SeasonInline(admin.TabularInline):
    model = Season
    extra = 0
    fields = ("number", "title", "is_enabled", "yt_playlist_id", "last_synced_at")
    readonly_fields = ("last_synced_at",)


class SeasonAdminForm(forms.ModelForm):
    sync_now = forms.BooleanField(
        required=False,
        help_text="If checked, will run sync immediately after saving to fetch episodes.",
        label="Sync now",
    )
    class Meta:
        model = Season
        fields = "__all__"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # For the Season admin, list all shows for the selected tenant,
        # ordered by newest first so recently created shows appear at the top.
        # This avoids confusing partial filters and still makes it easy to
        # find the latest content.
        if "show" in self.fields:
            qs = Show.objects.all()
            tenant_val = None
            if hasattr(self, "data") and self.data:
                tenant_val = self.data.get("tenant")
            if not tenant_val and getattr(self.instance, "tenant", None):
                tenant_val = self.instance.tenant
            if tenant_val:
                qs = qs.filter(tenant=tenant_val)
            qs = qs.order_by("-created_at")
            self.fields["show"].queryset = qs
        # Determine selected show to filter playlists by its channel
        show_obj = None
        show_id = None
        if hasattr(self, "data") and self.data:
            show_id = self.data.get("show") or self.data.get("show_id")
        if not show_id and getattr(self.instance, "show_id", None):
            show_id = self.instance.show_id
        if show_id:
            try:
                show_obj = Show.objects.select_related("channel").get(pk=show_id)
            except Show.DoesNotExist:
                show_obj = None

        # If we have a show with a channel, offer active playlists as choices for yt_playlist_id
        if "yt_playlist_id" in self.fields:
            choices = []
            if show_obj and show_obj.channel_id:
                pls = Playlist.objects.filter(channel_id=show_obj.channel_id, is_active=True).order_by("title")
                for pl in pls:
                    label = f"{pl.title} ({pl.id})"
                    choices.append((pl.id, label))
            if choices:
                self.fields["yt_playlist_id"].widget = forms.Select(choices=choices)
                self.fields["yt_playlist_id"].help_text = "Select from active playlists for this show's channel."
            else:
                self.fields["yt_playlist_id"].help_text = (
                    "YouTube playlist ID (PL...). No active playlists found for the selected channel; enter ID manually."
                )


@admin.register(Season)
class SeasonAdmin(admin.ModelAdmin):
    form = SeasonAdminForm
    list_display = ("show", "number", "tenant", "is_enabled", "yt_playlist_id", "last_synced_at")
    list_filter = ("tenant", "is_enabled")
    search_fields = ("show__title", "yt_playlist_id")
    inlines = [EpisodeInline]

    actions = ("run_sync_now",)

    fieldsets = (
        (None, {
            'fields': ("tenant", "show", "number", "title", "cover_upload", "cover_image", "is_enabled", "yt_playlist_id", "include_rules", "exclude_rules")
        }),
        ("Sync", {
            'fields': ("sync_now",),
        }),
        ("Timestamps", {
            'fields': ("last_synced_at",),
        }),
    )

    @admin.action(description="Run sync now (fetch episodes)")
    def run_sync_now(self, request, queryset):
        """Invoke sync_season management command for selected Season rows."""
        from django.core.management import call_command
        succeeded = 0
        failed = 0
        for season in queryset.select_related("show"):
            try:
                ref = f"{season.show.slug}:{season.number}"
                tenant = season.tenant
                call_command("sync_season", ref, f"--tenant={tenant}")
                succeeded += 1
            except Exception as exc:  # noqa: BLE001
                failed += 1
        self.message_user(
            request,
            f"Sync complete. Succeeded: {succeeded}, Failed: {failed}",
            fail_silently=True,
        )

    def _best_playlist_thumb(self, thumbnails: dict | None) -> str | None:
        if not thumbnails or not isinstance(thumbnails, dict):
            return None
        # Prefer maxres, then standard, then high, medium, default
        for key in ("maxres", "standard", "high", "medium", "default"):
            t = thumbnails.get(key)
            if isinstance(t, dict) and t.get("url"):
                return t["url"]
        # Some data shapes may be {"url": "..."}
        if thumbnails.get("url"):
            return thumbnails.get("url")
        return None

    def save_model(self, request, obj: Season, form, change):
        # If an upload is provided, mirror its URL into cover_image (preferred)
        try:
            if getattr(obj, "cover_upload", None):
                f = obj.cover_upload
                if f and hasattr(f, "url"):
                    obj.cover_image = f.url
        except Exception:
            pass
        # If cover_image is still blank but a playlist is selected, try to auto-fill from playlist thumbnails
        try:
            if not (obj.cover_image or "").strip() and (obj.yt_playlist_id or "").strip():
                pl = Playlist.objects.filter(id=obj.yt_playlist_id).first()
                if pl:
                    url = self._best_playlist_thumb(pl.thumbnails)
                    if url:
                        obj.cover_image = url
        except Exception:
            # Best-effort only; don't break save
            pass
        super().save_model(request, obj, form, change)
        try:
            sync_now = False
            if hasattr(form, 'cleaned_data'):
                sync_now = bool(form.cleaned_data.get('sync_now'))
            if sync_now:
                from django.core.management import call_command
                ref = f"{obj.show.slug}:{obj.number}"
                call_command("sync_season", ref, f"--tenant={obj.tenant}")
                self.message_user(request, f"Sync started for {ref}", fail_silently=True)
        except Exception:
            # Avoid breaking admin save if sync fails
            self.message_user(request, "Sync failed to start (see server logs).", fail_silently=True)

    # --- Dynamic dependent dropdown support ---
    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path("fetch_playlists/", self.admin_site.admin_view(self.fetch_playlists_view), name="series_season_fetch_playlists"),
        ]
        return custom + urls

    def fetch_playlists_view(self, request):
        """Return JSON list of active playlists for a given show id.

        Query params: show_id=<pk>
        Response: {"results": [{"id": "PL...", "title": "..."}, ...]}
        """
        show_id = request.GET.get("show_id")
        results = []
        if show_id:
            try:
                show_obj = Show.objects.select_related("channel").get(pk=show_id)
                pls = Playlist.objects.filter(channel_id=show_obj.channel_id, is_active=True).order_by("title")
                results = [{"id": pl.id, "title": pl.title} for pl in pls]
            except Show.DoesNotExist:
                results = []
        return JsonResponse({"results": results})

    class Media:
        js = ("series/season_admin.js",)

    # Thumbnails for a given playlist id (to allow selecting a specific cover image)
    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path("fetch_playlists/", self.admin_site.admin_view(self.fetch_playlists_view), name="series_season_fetch_playlists"),
            path("fetch_thumbnails/", self.admin_site.admin_view(self.fetch_thumbnails_view), name="series_season_fetch_thumbnails"),
        ]
        return custom + urls

    def fetch_thumbnails_view(self, request):
        """Return JSON thumbnails for a given playlist id.

        Query params: playlist_id=PL...
        Response: {"results": [{"key": "high", "url": "...", "width": 1280, "height": 720}, ...]}
        """
        pid = request.GET.get("playlist_id")
        results = []
        if pid:
            pl = Playlist.objects.filter(id=pid).first()
            thumbs = getattr(pl, "thumbnails", None) if pl else None
            if isinstance(thumbs, dict):
                # Normalize common YouTube shapes
                order = ["maxres", "standard", "high", "medium", "default"]
                for key in order:
                    t = thumbs.get(key)
                    if isinstance(t, dict) and t.get("url"):
                        results.append({
                            "key": key,
                            "url": t.get("url"),
                            "width": t.get("width"),
                            "height": t.get("height"),
                        })
                # Fallback single url shape
                if not results and thumbs.get("url"):
                    results.append({"key": "auto", "url": thumbs.get("url"), "width": None, "height": None})
        return JsonResponse({"results": results})


@admin.register(Episode)
class EpisodeAdmin(admin.ModelAdmin):
    list_display = (
        "season",
        "episode_number",
        "display_title",
        "visible",
        "status",
        "source_video_id",
        "updated_at",
    )
    list_filter = ("tenant", "status", "visible", "season__show")
    search_fields = ("title", "title_override", "source_video_id")


# --- Category admin with native color picker ---
class CategoryAdminForm(forms.ModelForm):
    class Meta:
        model = Category
        fields = "__all__"
        widgets = {
            'color': forms.TextInput(attrs={'type': 'color'}),
        }


@admin.register(Category)
class CategoryAdmin(admin.ModelAdmin):
    form = CategoryAdminForm
    list_display = ("name", "slug", "tenant", "color", "is_active", "display_order")
    list_filter = ("tenant", "is_active")
    search_fields = ("name", "slug")
    ordering = ("tenant", "display_order", "name")
