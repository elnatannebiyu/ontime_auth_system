from django.contrib import admin
from django.conf import settings
from pathlib import Path
from typing import Optional
from .models import Channel, Playlist, Video
from .forms import ChannelAdminForm, PlaylistAdminForm
import json
import shutil
import base64
from django.utils.safestring import mark_safe
from django import forms
from datetime import datetime
try:
    from PIL import Image
    _PIL_AVAILABLE = True
except Exception:  # noqa: BLE001
    _PIL_AVAILABLE = False


def _find_channel_folder_by_id_slug(id_slug: str) -> Optional[Path]:
    base = Path(settings.BASE_DIR) / "youtube_channels"
    if not base.exists():
        return None
    for child in base.iterdir():
        if not child.is_dir():
            continue
        candidate = child / "channel.v1.json"
        if candidate.exists():
            try:
                data = json.loads(candidate.read_text(encoding="utf-8"))
                if data.get("id") == id_slug:
                    return child
            except Exception:
                continue
    return None


@admin.register(Channel)
class ChannelAdmin(admin.ModelAdmin):
    form = ChannelAdminForm
    list_display = (
        "id_slug",
        "name_en",
        "name_am",
        "tenant",
        "youtube_handle",
        "youtube_channel_id",
        "is_active",
        "featured",
        "sort_order",
    )
    list_filter = ("tenant", "is_active", "featured", "language", "country")
    search_fields = ("id_slug", "name_en", "name_am")
    ordering = ("sort_order", "id_slug")
    readonly_fields = ("uid", "created_at", "updated_at", "logo_preview", "backups_preview")

    actions = (
        "activate_channels",
        "deactivate_channels",
        "resolve_youtube_channel_id",
        "sync_youtube_playlists",
        "sync_youtube_all",
        "cascade_activate_playlists",
        "cascade_deactivate_playlists",
    )

    @admin.action(description="Activate selected channels")
    def activate_channels(self, request, queryset):
        queryset.update(is_active=True)

    @admin.action(description="Deactivate selected channels")
    def deactivate_channels(self, request, queryset):
        queryset.update(is_active=False)

    @admin.action(description="Activate ALL playlists for selected channels")
    def cascade_activate_playlists(self, request, queryset):
        total = 0
        for ch in queryset:
            updated = ch.playlists.update(is_active=True)
            total += updated
        self.message_user(request, f"Activated {total} playlist(s) across {queryset.count()} channel(s).")

    @admin.action(description="Deactivate ALL playlists for selected channels")
    def cascade_deactivate_playlists(self, request, queryset):
        total = 0
        for ch in queryset:
            updated = ch.playlists.update(is_active=False)
            total += updated
        self.message_user(request, f"Deactivated {total} playlist(s) across {queryset.count()} channel(s).")

    def save_model(self, request, obj: Channel, form, change):
        """Ensure a channel folder exists; optionally save uploaded logo.

        Rules:
        - If folder for this channel id isn't found, create youtube_channels/<PrettyName>/.
        - Create a minimal channel.v1.json if not present.
        - If a file is uploaded, save it as icon.jpg and update images accordingly.
        - If no file uploaded, do not modify images (leave blank if blank).
        """
        super().save_model(request, obj, form, change)
        # If handle present but no channel id, try resolving on save (best effort)
        try:
            if obj.youtube_handle and not obj.youtube_channel_id:
                from . import youtube_api
                cid = youtube_api.resolve_channel_id(obj.youtube_handle)
                if cid:
                    obj.youtube_channel_id = cid
                    obj.save(update_fields=["youtube_channel_id", "updated_at"])
                    self.message_user(request, f"Resolved YouTube channel ID: {cid}")
        except Exception as exc:  # noqa: BLE001
            self.message_user(request, f"Could not resolve channel id: {exc}", level="warning")
        upload = form.cleaned_data.get("logo_upload") if hasattr(form, "cleaned_data") else None
        delete_logo = form.cleaned_data.get("delete_logo") if hasattr(form, "cleaned_data") else False
        delete_backups = form.cleaned_data.get("delete_backups") if hasattr(form, "cleaned_data") else []
        restore_backup = form.cleaned_data.get("restore_backup") if hasattr(form, "cleaned_data") else ""
        base_root = Path(settings.BASE_DIR) / "youtube_channels"
        base_root.mkdir(parents=True, exist_ok=True)

        # Find existing canonical folder; otherwise create a new one using a pretty name
        folder = _find_channel_folder_by_id_slug(obj.id_slug)
        if not folder:
            pretty = (obj.name_en or obj.name_am or obj.id_slug or "channel").strip()
            # Normalize whitespace
            pretty = " ".join(pretty.split())
            folder = base_root / pretty
            folder.mkdir(parents=True, exist_ok=True)

            # Write minimal channel.v1.json if missing
            json_path = folder / "channel.v1.json"
            if not json_path.exists():
                minimal = {
                    "tenant": obj.tenant,
                    "id": obj.id_slug,
                    "display": {
                        "default_locale": obj.default_locale,
                        "name": {"am": obj.name_am, "en": obj.name_en},
                    },
                    "availability": {"is_active": obj.is_active},
                    "lineup": {"sort_order": obj.sort_order, "featured": obj.featured},
                }
                json_path.write_text(json.dumps(minimal, ensure_ascii=False, indent=2), encoding="utf-8")
                self.message_user(
                    request,
                    f"Created youtube_channels/{folder.name}/channel.v1.json",
                )

        # If delete requested, remove existing icon and clear images first
        if delete_logo and folder:
            try:
                # Prefer path from images JSON; fallback to icon.jpg/png
                img_name = None
                if obj.images and isinstance(obj.images, list):
                    for itm in obj.images:
                        if isinstance(itm, dict) and itm.get("kind") == "logo" and itm.get("path"):
                            img_name = itm.get("path")
                            break
                candidates = [img_name] if img_name else []
                candidates += ["icon.jpg", "icon.png"]
                removed_any = False
                for name in candidates:
                    if not name:
                        continue
                    p = folder / name
                    if p.exists():
                        p.unlink()
                        removed_any = True
                # Clear images in model
                obj.images = []
                obj.save(update_fields=["images", "updated_at"])
                if removed_any:
                    self.message_user(request, f"Deleted existing icon(s) for {obj.id_slug} and cleared images.")
                else:
                    self.message_user(request, f"No existing icon found to delete for {obj.id_slug}.")
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"Failed to delete existing icon: {exc}", level="warning")

        # Handle deleting selected backups
        if delete_backups and folder:
            removed = 0
            for name in delete_backups:
                p = folder / name
                try:
                    if p.exists() and p.is_file() and p.name.startswith("old-"):
                        p.unlink()
                        removed += 1
                except Exception as exc:  # noqa: BLE001
                    self.message_user(request, f"Failed to delete backup {name}: {exc}", level="warning")
            if removed:
                self.message_user(request, f"Deleted {removed} backup icon(s).")

        # If restore requested, promote selected backup to current icon
        if restore_backup and folder:
            try:
                src = folder / restore_backup
                if src.exists() and src.is_file() and src.name.startswith("old-"):
                    dest = folder / "icon.jpg"
                    # rotate existing icon first
                    if dest.exists():
                        try:
                            ts = datetime.now().strftime("%Y%m%d-%H%M%S")
                            backup = folder / f"old-{ts}.jpg"
                            dest.rename(backup)
                        except Exception as exc:  # noqa: BLE001
                            self.message_user(request, f"Could not backup existing icon before restore: {exc}", level="warning")
                    src.rename(dest)
                    obj.images = [{"kind": "logo", "source": "folder", "path": "icon.jpg"}]
                    obj.save(update_fields=["images", "updated_at"])
                    self.message_user(request, f"Restored {restore_backup} as current icon.jpg.")
                    # If an upload was also provided, ignore it to avoid overriding restore
                    if upload:
                        self.message_user(request, "Upload provided together with restore; upload was ignored in favor of restore.", level="warning")
                        upload = None
                else:
                    self.message_user(request, f"Selected backup not found: {restore_backup}", level="warning")
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"Failed to restore backup {restore_backup}: {exc}", level="warning")

        if upload:
            # Persist uploaded file as icon.jpg, converting to JPEG if possible
            dest = folder / "icon.jpg"
            # Rotate existing icon to timestamped backup
            try:
                if dest.exists():
                    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
                    backup = folder / f"old-{ts}.jpg"
                    dest.rename(backup)
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"Could not backup existing icon.jpg: {exc}", level="warning")

            # Save/convert upload
            try:
                if _PIL_AVAILABLE:
                    # Convert via Pillow
                    from io import BytesIO
                    buf = BytesIO()
                    for chunk in upload.chunks():
                        buf.write(chunk)
                    buf.seek(0)
                    img = Image.open(buf).convert("RGB")
                    img.save(dest, format="JPEG", quality=90)
                else:
                    # Fallback: raw bytes to icon.jpg (may not be real JPEG but works in most browsers)
                    with dest.open("wb") as f:
                        for chunk in upload.chunks():
                            f.write(chunk)
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"Failed to write icon.jpg: {exc}", level="warning")

            # Update images JSON to point to this file
            obj.images = [{"kind": "logo", "source": "folder", "path": "icon.jpg"}]
            obj.save(update_fields=["images", "updated_at"])
            self.message_user(request, f"Logo saved to {dest.relative_to(Path(settings.BASE_DIR))} and images updated.")

    def logo_preview(self, obj: Channel):
        """Render a small preview of the channel logo if present."""
        try:
            folder = _find_channel_folder_by_id_slug(obj.id_slug)
            if not folder:
                return "—"
            # Determine image file name from images JSON or common defaults
            img_name = None
            if obj.images and isinstance(obj.images, list):
                for itm in obj.images:
                    if isinstance(itm, dict) and itm.get("kind") == "logo" and itm.get("path"):
                        img_name = itm.get("path")
                        break
            if not img_name:
                if (folder / "icon.jpg").exists():
                    img_name = "icon.jpg"
                elif (folder / "icon.png").exists():
                    img_name = "icon.png"
                else:
                    return "—"
            img_path = folder / img_name
            if not img_path.exists():
                return "—"
            data = img_path.read_bytes()
            ext = img_path.suffix.lower()
            mime = "image/png" if ext == ".png" else "image/jpeg"
            b64 = base64.b64encode(data).decode("ascii")
            html = f'<img src="data:{mime};base64,{b64}" style="max-height:120px;border:1px solid #ddd;padding:2px;border-radius:4px;" />'
            return mark_safe(html)
        except Exception:
            return "—"
    logo_preview.short_description = "Logo"

    def backups_preview(self, obj: Channel):
        """Render thumbnails for backup icons (old-*.jpg)."""
        try:
            folder = _find_channel_folder_by_id_slug(obj.id_slug)
            if not folder or not folder.exists():
                return "—"
            thumbs = []
            for p in sorted(folder.glob("old-*.jpg")):
                try:
                    data = p.read_bytes()
                    b64 = base64.b64encode(data).decode("ascii")
                    html = f'<div style="display:inline-block;margin:4px;text-align:center"><div><img src="data:image/jpeg;base64,{b64}" style="max-height:80px;border:1px solid #ddd;padding:2px;border-radius:4px;" /></div><div style="max-width:120px;overflow:hidden;text-overflow:ellipsis;font-size:11px">{p.name}</div></div>'
                    thumbs.append(html)
                except Exception:
                    continue
            return mark_safe(''.join(thumbs) if thumbs else "—")
        except Exception:
            return "—"
    backups_preview.short_description = "Backup Icons"

    @admin.action(description="Resolve YouTube Channel ID from handle (@...)")
    def resolve_youtube_channel_id(self, request, queryset):
        from . import youtube_api
        updated = 0
        for ch in queryset:
            try:
                handle_or_url = ch.youtube_handle or ""
                if not handle_or_url:
                    continue
                cid = youtube_api.resolve_channel_id(handle_or_url)
                if cid and cid != ch.youtube_channel_id:
                    ch.youtube_channel_id = cid
                    ch.save(update_fields=["youtube_channel_id", "updated_at"])
                    updated += 1
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"{ch.id_slug}: resolve failed: {exc}", level="warning")
        self.message_user(request, f"Resolved/updated {updated} channel ID(s).")

    @admin.action(description="Sync YouTube playlists (create/update latest)")
    def sync_youtube_playlists(self, request, queryset):
        from . import youtube_api
        created = 0
        updated = 0
        for ch in queryset:
            try:
                cid = ch.youtube_channel_id
                if not cid:
                    # Try resolve from handle on the fly
                    if ch.youtube_handle:
                        cid = youtube_api.resolve_channel_id(ch.youtube_handle)
                        if cid:
                            ch.youtube_channel_id = cid
                            ch.save(update_fields=["youtube_channel_id", "updated_at"])
                    if not cid:
                        self.message_user(request, f"{ch.id_slug}: missing youtube_channel_id and handle; skipped.", level="warning")
                        continue
                page = None
                while True:
                    data = youtube_api.list_playlists(cid, page_token=page, max_results=50)
                    for it in data.get("items", []):
                        pid = it.get("id")
                        title = it.get("title")
                        thumbs = it.get("thumbnails") or {}
                        count = int(it.get("itemCount") or 0)
                        obj, was_created = Playlist.objects.update_or_create(
                            id=pid,
                            defaults={
                                "channel": ch,
                                "title": title or "",
                                "thumbnails": thumbs,
                                "item_count": count,
                            },
                        )
                        if was_created:
                            created += 1
                        else:
                            updated += 1
                    page = data.get("nextPageToken")
                    if not page:
                        break
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"{ch.id_slug}: sync failed: {exc}", level="warning")
        self.message_user(request, f"Playlists upserted. created={created}, updated={updated}")

    @admin.action(description="Sync YouTube (playlists + videos)")
    def sync_youtube_all(self, request, queryset):
        from . import youtube_api
        from datetime import datetime, timezone
        playlists_created = 0
        playlists_updated = 0
        videos_created = 0
        videos_updated = 0
        for ch in queryset:
            try:
                # 1) Ensure channel id
                cid = ch.youtube_channel_id
                if not cid and ch.youtube_handle:
                    cid = youtube_api.resolve_channel_id(ch.youtube_handle)
                    if cid:
                        ch.youtube_channel_id = cid
                        ch.save(update_fields=["youtube_channel_id", "updated_at"])
                if not cid:
                    self.message_user(request, f"{ch.id_slug}: missing youtube_channel_id and handle; skipped.", level="warning")
                    continue
                # 2) Sync playlists
                page = None
                while True:
                    data = youtube_api.list_playlists(cid, page_token=page, max_results=50)
                    for it in data.get("items", []):
                        pid = it.get("id")
                        title = it.get("title")
                        thumbs = it.get("thumbnails") or {}
                        count = int(it.get("itemCount") or 0)
                        obj, was_created = Playlist.objects.update_or_create(
                            id=pid,
                            defaults={
                                "channel": ch,
                                "title": title or "",
                                "thumbnails": thumbs,
                                "item_count": count,
                            },
                        )
                        if was_created:
                            playlists_created += 1
                        else:
                            playlists_updated += 1
                    page = data.get("nextPageToken")
                    if not page:
                        break
                # 3) Sync videos (active playlists if any, else all)
                playlists = list(ch.playlists.filter(is_active=True)) or list(ch.playlists.all())
                for pl in playlists:
                    page = None
                    while True:
                        data = youtube_api.list_playlist_items(pl.id, page_token=page, max_results=50)
                        for it in data.get("items", []):
                            vid = it.get("videoId")
                            published_at = it.get("publishedAt")
                            dt = None
                            if published_at:
                                try:
                                    dt = datetime.strptime(published_at, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
                                except Exception:
                                    dt = None
                            obj, created = Video.objects.update_or_create(
                                playlist=pl,
                                video_id=vid,
                                defaults={
                                    "channel": ch,
                                    "title": it.get("title") or "",
                                    "thumbnails": it.get("thumbnails") or {},
                                    "position": it.get("position"),
                                    "published_at": dt,
                                    "is_active": True,
                                },
                            )
                            if created:
                                videos_created += 1
                            else:
                                videos_updated += 1
                        page = data.get("nextPageToken")
                        if not page:
                            break
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"{ch.id_slug}: sync failed: {exc}", level="warning")
        self.message_user(
            request,
            f"Sync complete. playlists(created={playlists_created}, updated={playlists_updated}), "
            f"videos(created={videos_created}, updated={videos_updated})",
        )


@admin.register(Playlist)
class PlaylistAdmin(admin.ModelAdmin):
    form = PlaylistAdminForm
    list_display = ("id", "title", "channel", "item_count", "is_active", "last_synced_at")
    list_filter = ("channel", "is_active")
    search_fields = ("id", "title", "channel__id_slug", "channel__name_en", "channel__name_am")
    ordering = ("channel", "title")
    actions = ("activate_playlists", "deactivate_playlists")

    @admin.action(description="Activate selected playlists")
    def activate_playlists(self, request, queryset):
        queryset.update(is_active=True)

    @admin.action(description="Deactivate selected playlists")
    def deactivate_playlists(self, request, queryset):
        queryset.update(is_active=False)


@admin.register(Video)
class VideoAdmin(admin.ModelAdmin):
    class VideoAdminForm(forms.ModelForm):
        # Optional helper field: allow pasting a full YouTube URL to auto-fill video_id
        video_url = forms.CharField(
            required=False,
            help_text=(
                "Paste a YouTube URL here (watch, youtu.be, embed, or shorts). "
                "We'll auto-fill the Video ID."
            ),
            label="YouTube URL",
        )

        class Meta:
            model = Video
            fields = "__all__"

        def __init__(self, *args, **kwargs):
            super().__init__(*args, **kwargs)
            # Allow leaving video_id empty so we can derive it from video_url
            if "video_id" in self.fields:
                self.fields["video_id"].required = False
            # Make channel optional (we can derive from playlist in clean())
            if "channel" in self.fields:
                self.fields["channel"].required = False
            # Filter playlist choices by selected channel and active status
            ch_id = None
            # If this is a bound form, prefer posted channel
            if hasattr(self, "data") and self.data:
                ch_id = self.data.get("channel") or self.data.get("channel_id")
            # Fallback to instance
            if not ch_id and getattr(self.instance, "channel_id", None):
                ch_id = self.instance.channel_id
            if "playlist" in self.fields:
                if ch_id:
                    self.fields["playlist"].queryset = Playlist.objects.filter(is_active=True, channel_id=ch_id)
                    self.fields["playlist"].help_text = "Active playlists for the selected channel."
                else:
                    # Show all active playlists until a channel is selected
                    self.fields["playlist"].queryset = Playlist.objects.filter(is_active=True)
                    self.fields["playlist"].help_text = "Active playlists across all channels (select a Channel to narrow)."

        def clean_playlist(self):
            pl = self.cleaned_data.get("playlist")
            if pl and not pl.is_active:
                raise forms.ValidationError("Only active playlists can be selected.")
            return pl

        def _extract_video_id(self, text: str) -> Optional[str]:
            if not text:
                return None
            text = text.strip()
            # If it already looks like a plain 11-char ID, accept it
            import re
            if re.fullmatch(r"[A-Za-z0-9_-]{11}", text):
                return text
            # Try URL parsing patterns
            try:
                import urllib.parse as _up
                parsed = _up.urlparse(text)
                # youtu.be/<id>
                if parsed.netloc.endswith("youtu.be") and parsed.path:
                    vid = parsed.path.lstrip("/")
                    if re.fullmatch(r"[A-Za-z0-9_-]{11}", vid):
                        return vid
                # youtube watch?v=<id>
                if "youtube." in parsed.netloc:
                    qs = _up.parse_qs(parsed.query)
                    v = qs.get("v", [None])[0]
                    if v and re.fullmatch(r"[A-Za-z0-9_-]{11}", v):
                        return v
                    # /embed/<id> or /shorts/<id>
                    parts = [p for p in parsed.path.split("/") if p]
                    if len(parts) >= 2 and parts[0] in {"embed", "shorts"}:
                        cand = parts[1]
                        if re.fullmatch(r"[A-Za-z0-9_-]{11}", cand):
                            return cand
            except Exception:
                pass
            return None

        def clean_video_id(self):
            vid = self.cleaned_data.get("video_id")
            if vid:
                parsed = self._extract_video_id(vid)
                if parsed:
                    return parsed
            # If not provided or not parseable, leave as-is for now; may get from video_url in clean()
            return vid

        def clean(self):
            cleaned = super().clean()
            url = cleaned.get("video_url")
            vid = cleaned.get("video_id")
            if url:
                parsed = self._extract_video_id(url)
                if not parsed:
                    self.add_error("video_url", "Could not extract a valid YouTube video ID from the URL.")
                else:
                    cleaned["video_id"] = parsed
            # Ensure we end up with a valid video_id
            if not cleaned.get("video_id"):
                self.add_error("video_id", "Video ID is required (paste a valid YouTube URL or the 11-character ID).")
            # If channel not explicitly provided, derive from playlist
            pl = cleaned.get("playlist")
            ch = cleaned.get("channel")
            if pl and not ch:
                cleaned["channel"] = pl.channel
            return cleaned

    class PlaylistActiveFilter(admin.SimpleListFilter):
        title = "Playlist active"
        parameter_name = "playlist_active"

        def lookups(self, request, model_admin):
            return (
                ("1", "Yes"),
                ("0", "No"),
            )

        def queryset(self, request, queryset):
            val = self.value()
            if val == "1":
                return queryset.filter(playlist__is_active=True)
            if val == "0":
                return queryset.filter(playlist__is_active=False)
            return queryset

    list_display = (
        "video_id",
        "title",
        "channel",
        "playlist",
        "playlist_is_active",
        "position",
        "published_at",
        "is_active",
        "last_synced_at",
    )
    list_filter = ("channel", "playlist", "is_active", PlaylistActiveFilter)
    search_fields = (
        "video_id",
        "title",
        "playlist__id",
        "channel__id_slug",
        "channel__name_en",
        "channel__name_am",
    )
    ordering = ("-published_at", "playlist", "position")
    readonly_fields = ("last_synced_at",)

    form = VideoAdminForm

    # Explicit field order to include the helper video_url
    fields = (
        "channel",
        "playlist",
        "video_url",
        "video_id",
        "title",
        "position",
        "published_at",
        "is_active",
        "thumbnails",
        "last_synced_at",
    )

    def formfield_for_foreignkey(self, db_field, request, **kwargs):
        if db_field.name == "playlist":
            kwargs["queryset"] = Playlist.objects.filter(is_active=True)
        return super().formfield_for_foreignkey(db_field, request, **kwargs)

    def get_queryset(self, request):
        qs = super().get_queryset(request)
        # Apply default filter to only show videos from active playlists,
        # unless the admin user explicitly uses the sidebar filter.
        if "playlist_active" not in request.GET and "playlist__is_active__exact" not in request.GET:
            qs = qs.filter(playlist__is_active=True)
        return qs

    def playlist_is_active(self, obj):  # noqa: D401
        """Whether the related playlist is active."""
        return bool(getattr(obj.playlist, "is_active", False))

    playlist_is_active.boolean = True  # type: ignore[attr-defined]
    playlist_is_active.admin_order_field = "playlist__is_active"  # type: ignore[attr-defined]
    playlist_is_active.short_description = "Playlist active"  # type: ignore[attr-defined]
