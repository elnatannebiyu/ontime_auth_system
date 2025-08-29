from django import forms
from .models import Channel, Playlist
from django.conf import settings
from pathlib import Path
import json


class ChannelAdminForm(forms.ModelForm):
    logo_upload = forms.FileField(required=False, help_text="Upload a logo image to save into the channel folder.")
    delete_logo = forms.BooleanField(required=False, help_text="Delete existing icon file and clear images.")
    delete_backups = forms.MultipleChoiceField(
        required=False,
        help_text="Select old backup icons to delete.",
        choices=(),
        widget=forms.SelectMultiple,
    )
    restore_backup = forms.ChoiceField(
        required=False,
        help_text="Promote a selected backup to become the current icon.jpg.",
        choices=(),
    )

    class Meta:
        model = Channel
        fields = "__all__"

    def __init__(self, *args, **kwargs):
        super().__init__(*args, **kwargs)
        # Populate backup choices based on instance
        instance = kwargs.get("instance") or getattr(self, "instance", None)
        choices = []
        restore_choices = [("", "— none —")]
        if instance and getattr(instance, "id_slug", None):
            base = Path(settings.BASE_DIR) / "youtube_channels"
            if base.exists():
                # Find folder by matching channel.v1.json id
                folder = None
                for child in base.iterdir():
                    if not child.is_dir():
                        continue
                    f = child / "channel.v1.json"
                    if f.exists():
                        try:
                            data = json.loads(f.read_text(encoding="utf-8"))
                            if data.get("id") == instance.id_slug:
                                folder = child
                                break
                        except Exception:
                            continue
                if folder:
                    for p in folder.iterdir():
                        name = p.name
                        if name.startswith("old-") and p.is_file():
                            choices.append((name, name))
                            restore_choices.append((name, name))
        self.fields["delete_backups"].choices = choices
        self.fields["restore_backup"].choices = restore_choices


class PlaylistAdminForm(forms.ModelForm):
    playlist_url = forms.URLField(
        required=False,
        help_text="Paste a YouTube playlist URL (with ?list=...) to auto-fill metadata",
        label="YouTube Playlist URL",
    )

    class Meta:
        model = Playlist
        fields = [
            "id",
            "channel",
            "title",
            "thumbnails",
            "item_count",
            "is_active",
            "playlist_url",
        ]

    def clean(self):
        cleaned = super().clean()
        url = cleaned.get("playlist_url")
        pid = cleaned.get("id")
        channel = cleaned.get("channel")
        if not channel:
            raise forms.ValidationError("Please select a Channel for this playlist.")
        if not pid and not url:
            # Allow manual creation with explicit ID or via URL
            return cleaned
        if url and not pid:
            from . import youtube_api
            extracted = youtube_api.playlist_id_from_url(url)
            if not extracted:
                raise forms.ValidationError("Could not extract playlist ID from URL.")
            cleaned["id"] = extracted
            self.data = self.data.copy()
            self.data["id"] = extracted
        return cleaned

    def save(self, commit=True):
        """On save, if a URL or ID is provided, fetch metadata and upsert."""
        from . import youtube_api
        pid = self.cleaned_data.get("id")
        url = self.cleaned_data.get("playlist_url")
        if url and not pid:
            pid = youtube_api.playlist_id_from_url(url)
        if pid:
            try:
                meta = youtube_api.get_playlist(pid)
            except youtube_api.YouTubeAPIError as exc:
                raise forms.ValidationError(f"Failed to fetch playlist metadata: {exc}") from exc
            if not meta or not meta.get("id"):
                raise forms.ValidationError("Playlist not found or not accessible. Check that the playlist is public and the ID is correct.")
            self.instance.id = meta.get("id") or pid
            self.instance.title = meta.get("title") or self.cleaned_data.get("title") or ""
            self.instance.thumbnails = meta.get("thumbnails") or {}
            self.instance.item_count = int(meta.get("itemCount") or 0)
        return super().save(commit=commit)
