from django.contrib import admin
from .models import Live, LiveSchedule
from django.utils.safestring import mark_safe


@admin.register(Live)
class LiveAdmin(admin.ModelAdmin):
    list_display = (
        "channel",
        "tenant",
        "playback_type",
        "is_active",
        "preview_link",
        "updated_at",
    )
    list_filter = ("tenant", "is_active", "playback_type")
    search_fields = (
        "channel__id_slug",
        "channel__name_en",
        "channel__name_am",
        "title",
    )
    autocomplete_fields = ("channel",)
    readonly_fields = ("created_at", "updated_at", "preview_link")
    fieldsets = (
        ("Link", {"fields": ("channel", "tenant")}),
        ("Display", {"fields": ("title", "description", "poster_url")} ),
        ("Playback", {"fields": ("playback_url", "playback_type", "drm")} ),
        ("Flags", {"fields": ("is_active", "is_previewable", "tags", "meta", "preview_link")} ),
        ("Timestamps", {"fields": ("created_at", "updated_at")} ),
    )

    def save_model(self, request, obj: Live, form, change):
        # Ensure tenant mirrors channel if not explicitly set
        if obj.channel and not obj.tenant:
            obj.tenant = getattr(obj.channel, "tenant", obj.tenant)
        super().save_model(request, obj, form, change)

    def preview_link(self, obj: Live):  # type: ignore[override]
        try:
            slug = getattr(obj.channel, "id_slug", "")
            tenant = obj.tenant or "ontime"
            url = f"/api/live/preview/{slug}/?tenant={tenant}"
            return mark_safe(f'<a href="{url}" target="_blank" rel="noopener">Preview</a>')
        except Exception:
            return "—"
    preview_link.short_description = "Preview"  # type: ignore[attr-defined]


@admin.register(LiveSchedule)
class LiveScheduleAdmin(admin.ModelAdmin):
    list_display = ("live", "title", "start_at", "end_at", "is_active")
    list_filter = ("is_active",)
    search_fields = ("title", "live__channel__id_slug", "live__channel__name_en", "live__channel__name_am")
    autocomplete_fields = ("live",)
    readonly_fields = ("created_at", "updated_at")
    fieldsets = (
        (None, {"fields": ("live", "title", "description")} ),
        ("Schedule", {"fields": ("start_at", "end_at", "is_active")} ),
        ("Timestamps", {"fields": ("created_at", "updated_at")} ),
    )
