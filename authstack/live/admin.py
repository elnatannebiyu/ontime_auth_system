from django.contrib import admin
from .models import Live, LiveSchedule, LiveRadio
from django.utils.safestring import mark_safe
from django.urls import path
from django.template.response import TemplateResponse
from django import forms
from io import StringIO
from django.core import management


@admin.register(Live)
class LiveAdmin(admin.ModelAdmin):
    list_display = (
        "channel",
        "tenant",
        "playback_type",
        "is_active",
        "updated_at",
        "preview_link",
    )
    list_filter = ("tenant", "is_active", "playback_type", "is_previewable", "is_local", "is_verified")
    search_fields = (
        "channel__id_slug",
        "channel__name_en",
        "channel__name_am",
        "title",
        "description",
        "country",
        "city",
        "category",
    )
    autocomplete_fields = ("channel",)
    readonly_fields = ("created_at", "updated_at", "preview_link",)
    fieldsets = (
        ("Link", {"fields": ("channel", "tenant")} ),
        ("Basic Info", {"fields": ("title", "description", "language", "country", "city", "category", "is_local")} ),
        ("Streaming Info", {"fields": ("playback_url", "playback_type", "drm", "stream_url", "backup_stream_url", "stream_type", "bitrate", "resolution", "aspect_ratio", "is_verified", "requires_vpn")} ),
        ("Branding", {"fields": ("poster_url", "logo", "banner_image", "thumbnail_url", "website_url", "facebook_url", "twitter_url", "instagram_url", "youtube_url")} ),
        ("Access & Monetization", {"fields": ("is_free", "requires_login", "price_per_month", "payment_provider", "access_token_expiry", "region_lock", "license_expiry_date", "ad_enabled")} ),
        ("Scheduling & Content", {"fields": ("has_epg", "epg_url", "schedule_updated_at", "current_program", "next_program")} ),
        ("Analytics", {"fields": ("viewer_count", "total_views", "stream_health", "priority", "listener_count", "total_listens", "added_by")} ),
        ("Flags", {"fields": ("is_active", "is_previewable", "tags", "meta", "preview_link")} ),
        ("Timestamps", {"fields": ("created_at", "updated_at")} ),
    )

    def save_model(self, request, obj: Live, form, change):
        # Ensure tenant mirrors channel if not explicitly set
        if obj.channel and not obj.tenant:
            obj.tenant = getattr(obj.channel, "tenant", obj.tenant)
        # Auto-set added_by on create
        if not change and not obj.added_by:
            try:
                obj.added_by = request.user if request and getattr(request, "user", None) and request.user.is_authenticated else None
            except Exception:
                pass
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


@admin.register(LiveRadio)
class LiveRadioAdmin(admin.ModelAdmin):
    change_list_template = "admin/live/liveradio/change_list.html"
    list_display = ("name", "tenant", "is_active", "is_verified", "last_check_ok", "updated_at", "preview_link", "listener_count", "total_listens")
    list_filter = ("tenant", "is_active", "is_verified")
    search_fields = ("name", "slug", "description", "city", "country", "category")
    readonly_fields = ("created_at", "updated_at",)
    actions = ("action_health_check",)
    fieldsets = (
        ("Link", {"fields": ("channel", "tenant")} ),
        ("Basic Info", {"fields": ("name", "slug", "description", "language", "country", "city", "category")} ),
        ("Streaming Info", {"fields": ("stream_url", "backup_stream_url", "bitrate", "format", "is_active", "is_verified")} ),
        ("Branding", {"fields": ("logo", "banner_image", "website_url", "facebook_url", "twitter_url", "instagram_url")} ),
        ("Access", {"fields": ("is_free", "price_per_month", "requires_login", "payment_provider", "access_token_expiry")} ),
        ("Analytics", {"fields": ("listener_count", "total_listens", "priority", "added_by")} ),
        ("Diagnostics", {"fields": ("last_check_ok", "last_check_at", "last_error")} ),
        ("Timestamps", {"fields": ("created_at", "updated_at")} ),
    )

    def save_model(self, request, obj: LiveRadio, form, change):
        if not change and not obj.added_by:
            try:
                obj.added_by = request.user if request and getattr(request, "user", None) and request.user.is_authenticated else None
            except Exception:
                pass
        super().save_model(request, obj, form, change)

    def preview_link(self, obj: LiveRadio):  # type: ignore[override]
        try:
            tenant = obj.tenant or "ontime"
            url = f"/api/live/radio/preview/{obj.slug}/?tenant={tenant}"
            return mark_safe(f'<a href="{url}" target="_blank" rel="noopener">Preview</a>')
        except Exception:
            return "—"
    preview_link.short_description = "Preview"  # type: ignore[attr-defined]

    def action_health_check(self, request, queryset):
        from django.core import management
        count = 0
        for radio in queryset:
            # Run single check using management command with slug to avoid long blocks
            try:
                management.call_command(
                    "check_radio_health",
                    tenant=radio.tenant,
                    slug=radio.slug,
                    set_verified_on_pass=True,
                    set_inactive_on_fail=True,
                    verbosity=0,
                )
                count += 1
            except Exception as e:
                # continue to next without raising
                pass
        self.message_user(request, f"Health check executed for {count} station(s)")
    action_health_check.short_description = "Run Health Check for selected"  # type: ignore[attr-defined]

    # --- Import from Radio Browser (Admin UI) ---
    class ImportRadiosForm(forms.Form):
        tenant = forms.CharField(initial="ontime", required=True)
        country = forms.CharField(initial="Ethiopia", required=True)
        limit = forms.IntegerField(initial=100, min_value=1, max_value=500)
        mirror = forms.ChoiceField(choices=[], required=False)

    def get_urls(self):
        urls = super().get_urls()
        custom = [
            path("import/", self.admin_site.admin_view(self.import_radios_view), name="live_liveradio_import"),
        ]
        return custom + urls

    def import_radios_view(self, request):
        # Prepare form with mirror choices
        try:
            from .management.commands.import_radio_stations import PREFERRED_MIRRORS
        except Exception:
            PREFERRED_MIRRORS = [
                "https://de1.api.radio-browser.info/json",
                "https://de2.api.radio-browser.info/json",
                "https://at1.api.radio-browser.info/json",
                "https://nl1.api.radio-browser.info/json",
            ]
        mirror_choices = [("auto", "Auto (try mirrors) ")] + [(m, m) for m in PREFERRED_MIRRORS]

        class _F(self.ImportRadiosForm):
            pass
        _F.base_fields["mirror"].choices = mirror_choices  # type: ignore[attr-defined]

        context = dict(
            self.admin_site.each_context(request),
        )
        message = None
        output = None
        if request.method == "POST":
            form = _F(request.POST)
            if form.is_valid():
                tenant = form.cleaned_data["tenant"].strip()
                country = form.cleaned_data["country"].strip()
                limit = int(form.cleaned_data["limit"])
                mirror = form.cleaned_data.get("mirror")
                out = StringIO()
                kwargs = {"tenant": tenant, "country": country, "limit": limit, "verbosity": 1, "stdout": out}
                if mirror and mirror != "auto":
                    kwargs["mirror"] = mirror
                try:
                    management.call_command("import_radio_stations", **kwargs)
                    output = out.getvalue()
                    message = "Import finished. Review the summary below."
                except Exception as e:
                    output = out.getvalue() + f"\nError: {e}"
                    message = "Import failed. See output below."
        else:
            form = _F()

        context.update({
            "opts": self.model._meta,
            "form": form,
            "title": "Import Radios from Radio Browser",
            "has_view_permission": self.has_view_permission(request),
            "message": message,
            "output": output,
        })
        return TemplateResponse(request, "admin/live/liveradio/import.html", context)


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
