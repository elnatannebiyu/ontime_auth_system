# --- Helpers: YouTube video_id normalization for dedupe ---
def _yt_video_id_from_url(url: str | None) -> str | None:
    if not url:
        return None
    try:
        import urllib.parse as _up
        p = _up.urlparse(url)
        host = (p.netloc or '').lower()
        path = p.path or ''
        qs = _up.parse_qs(p.query)
        # https://www.youtube.com/watch?v=ID
        if 'v' in qs and qs['v']:
            return qs['v'][0]
        # https://youtu.be/ID or /shorts/ID
        parts = [s for s in path.split('/') if s]
        if host.endswith('youtu.be') and parts:
            return parts[0]
        if host.endswith('youtube.com') and len(parts) >= 2 and parts[0] in {'shorts', 'embed', 'live'}:
            return parts[1]
    except Exception:
        return None
    return None


def _yt_video_id_via_ytdlp(url: str | None, timeout_sec: int = 5) -> str | None:
    if not url:
        return None
    try:
        import subprocess, shlex
        proc = subprocess.run(['yt-dlp', '-s', '--get-id', url], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=timeout_sec)
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip().splitlines()[0].strip()
    except Exception:
        return None
    return None
from rest_framework import viewsets, filters, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response
from rest_framework.views import APIView
from django.http import FileResponse
from django.conf import settings
from pathlib import Path
import os
import json
from datetime import datetime, timedelta, timezone as dt_timezone
import hashlib
import random
import hmac
import base64
from django.db.models import Max, F, Q

from .models import Channel, Playlist, Video, ShortJob
from .serializers import ChannelSerializer, PlaylistSerializer, VideoSerializer, ShortJobSerializer, CreateShortJobSerializer
from . import youtube_api

# Swagger imports guarded to avoid hard dependency in production where drf_yasg/pkg_resources may be unavailable
_ENABLE_SWAGGER = getattr(settings, 'ENABLE_SWAGGER', False) or settings.DEBUG
try:
    if _ENABLE_SWAGGER:
        from drf_yasg import openapi  # type: ignore
        from drf_yasg.utils import swagger_auto_schema  # type: ignore
    else:
        raise ImportError
except Exception:
    # Minimal shims: no-op decorator and simple openapi namespace with Parameter helper
    def swagger_auto_schema(*args, **kwargs):  # type: ignore
        def _decorator(func):
            return func
        return _decorator

    class _OpenApiShim:  # type: ignore
        IN_HEADER = 'header'
        IN_QUERY = 'query'
        TYPE_STRING = 'string'
        TYPE_INTEGER = 'integer'

        class Parameter:  # type: ignore
            def __init__(self, name, in_, description='', type=None, required=False, default=None):
                self.name = name
                self.in_ = in_
                self.description = description
                self.type = type
                self.required = required
                self.default = default

    openapi = _OpenApiShim()  # type: ignore


class ChannelViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Channel.objects.all()
    serializer_class = ChannelSerializer
    lookup_field = "id_slug"
    # Read-only for any authenticated user. Mutations are guarded inside actions with explicit checks.
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["id_slug", "name_en", "name_am"]
    ordering_fields = ["sort_order", "id_slug", "updated_at"]

    # Swagger header parameter for tenancy
    PARAM_TENANT = openapi.Parameter(
        name="X-Tenant-Id",
        in_=openapi.IN_HEADER,
        description="Tenant slug (e.g., ontime)",
        type=openapi.TYPE_STRING,
        required=True,
    )

    # Swagger query params for YouTube helpers
    PARAM_HANDLE = openapi.Parameter(
        name="handle",
        in_=openapi.IN_QUERY,
        description="YouTube channel handle, starting with @ (e.g., @ebstvWorldwide). Optional if channel_id provided.",
        type=openapi.TYPE_STRING,
        required=False,
    )
    PARAM_CHANNEL_ID = openapi.Parameter(
        name="channel_id",
        in_=openapi.IN_QUERY,
        description="YouTube channel ID (e.g., UC_x5XG1OV2P6uZZ5FSM9Ttw). Optional if handle provided.",
        type=openapi.TYPE_STRING,
        required=False,
    )
    PARAM_PAGE_TOKEN = openapi.Parameter(
        name="page_token",
        in_=openapi.IN_QUERY,
        description="YouTube API pageToken for pagination.",
        type=openapi.TYPE_STRING,
        required=False,
    )
    PARAM_MAX_RESULTS = openapi.Parameter(
        name="max_results",
        in_=openapi.IN_QUERY,
        description="Max results per page (default 25).",
        type=openapi.TYPE_INTEGER,
        required=False,
    )
    PARAM_PLAYLIST_ID = openapi.Parameter(
        name="playlist_id",
        in_=openapi.IN_QUERY,
        description="YouTube playlist ID (or 'list' query key). Optional if playlist_url provided.",
        type=openapi.TYPE_STRING,
        required=False,
    )
    PARAM_PLAYLIST_URL = openapi.Parameter(
        name="playlist_url",
        in_=openapi.IN_QUERY,
        description="Full playlist URL (the server will extract list=...). Optional if playlist_id provided.",
        type=openapi.TYPE_STRING,
        required=False,
    )

    def get_queryset(self):
        qs = super().get_queryset()
        # Enforce active-only for non-admins; allow admins to override via ?is_active=
        user = self.request.user
        if user.is_staff or user.has_perm("onchannels.change_channel"):
            is_active = self.request.query_params.get("is_active", "true")
            if is_active in {"true", "false", "1", "0"}:
                qs = qs.filter(is_active=is_active in {"true", "1"})
        else:
            qs = qs.filter(is_active=True)
        tenant = self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"
        qs = qs.filter(tenant=tenant)
        return qs

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    @action(detail=True, methods=["get"], url_path="logo")
    def logo(self, request, pk=None, id_slug=None, **kwargs):
        """Serve the channel logo file as an image stream.

        Looks up the channel folder under BASE_DIR/youtube_channels by scanning
        channel.v1.json for a matching id (id_slug). Then determines the image
        filename either from the Channel.images JSON (kind=logo, path), or
        defaults to icon.jpg/png. Returns 404 JSON if not found.
        """
        # DRF will pass id_slug as kwarg when lookup_field = 'id_slug'
        # self.get_object() respects lookup_field automatically
        channel = self.get_object()
        base_root = Path(settings.BASE_DIR) / "youtube_channels"
        if not base_root.exists():
            return Response({"detail": "Channel media root not found."}, status=status.HTTP_404_NOT_FOUND)

        folder = None
        # Try to find canonical folder by scanning channel.v1.json files
        try:
            for child in base_root.iterdir():
                if not child.is_dir():
                    continue
                meta = child / "channel.v1.json"
                if meta.exists():
                    try:
                        data = json.loads(meta.read_text(encoding="utf-8"))
                        if data.get("id") == channel.id_slug:
                            folder = child
                            break
                    except Exception:
                        continue
        except Exception:
            folder = None

        # Fallback: match folder by name case-insensitively (e.g., EBS for id_slug 'ebs')
        if not folder:
            try:
                slug_lc = (channel.id_slug or "").lower()
                for child in base_root.iterdir():
                    if child.is_dir() and child.name.lower() == slug_lc:
                        folder = child
                        break
            except Exception:
                pass

        if not folder or not folder.exists():
            return Response({"detail": "Channel folder not found."}, status=status.HTTP_404_NOT_FOUND)

        # Determine image file name from images JSON or common defaults
        img_name = None
        imgs = getattr(channel, "images", None)
        if imgs and isinstance(imgs, list):
            for itm in imgs:
                if isinstance(itm, dict) and itm.get("kind") == "logo" and itm.get("path"):
                    img_name = itm.get("path")
                    break
        candidates = [img_name] if img_name else []
        candidates += ["icon.jpg", "icon.png"]

        img_path = None
        for name in candidates:
            if not name:
                continue
            p = folder / name
            if p.exists() and p.is_file():
                img_path = p
                break

        if not img_path:
            return Response({"detail": "Logo image not found."}, status=status.HTTP_404_NOT_FOUND)

        # Guess mime type from extension
        ext = img_path.suffix.lower()
        content_type = "image/png" if ext == ".png" else "image/jpeg"
        try:
            return FileResponse(open(img_path, "rb"), content_type=content_type)
        except Exception:
            return Response({"detail": "Failed to read logo image."}, status=status.HTTP_500_INTERNAL_SERVER_ERROR)

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="activate")
    def activate(self, request, pk=None):
        # Require change permission explicitly for this custom action
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        channel.is_active = True
        channel.save(update_fields=["is_active", "updated_at"])
        return Response(ChannelSerializer(channel).data)

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="deactivate")
    def deactivate(self, request, pk=None):
        # Require change permission explicitly for this custom action
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        channel.is_active = False
        channel.save(update_fields=["is_active", "updated_at"])
        return Response(ChannelSerializer(channel).data)

    @swagger_auto_schema(
        manual_parameters=[
            PARAM_TENANT,
            PARAM_HANDLE,
            PARAM_CHANNEL_ID,
            PARAM_PAGE_TOKEN,
            PARAM_MAX_RESULTS,
        ]
    )
    @action(detail=False, methods=["get"], url_path="yt/playlists")
    def yt_playlists(self, request):
        """List playlists for a channel by channel_id or handle/url (?channel_id=.. or ?handle=..)."""
        channel_id = request.query_params.get("channel_id")
        handle = request.query_params.get("handle")
        page_token = request.query_params.get("page_token")
        max_results = int(request.query_params.get("max_results", 25))
        try:
            if not channel_id:
                if not handle:
                    return Response({"detail": "Provide channel_id or handle."}, status=status.HTTP_400_BAD_REQUEST)
                channel_id = youtube_api.resolve_channel_id(handle)
                if not channel_id:
                    return Response({"detail": "Could not resolve channel id from handle/url."}, status=status.HTTP_404_NOT_FOUND)
            data = youtube_api.list_playlists(channel_id, page_token=page_token, max_results=max_results)
            return Response(data)
        except youtube_api.YouTubeAPIError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="playlists/cascade-activate")
    def cascade_activate_playlists(self, request, pk=None):
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        changed = channel.playlists.update(is_active=True)
        return Response({"updated": changed})

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="playlists/cascade-deactivate")
    def cascade_deactivate_playlists(self, request, pk=None):
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        changed = channel.playlists.update(is_active=False)
        return Response({"updated": changed})

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="yt/sync-playlists")
    def sync_playlists(self, request, pk=None):
        """Sync (create/update) all public playlists for this channel from YouTube."""
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        created = 0
        updated_count = 0
        try:
            cid = channel.youtube_channel_id
            if not cid and channel.youtube_handle:
                cid = youtube_api.resolve_channel_id(channel.youtube_handle)
                if cid and cid != channel.youtube_channel_id:
                    channel.youtube_channel_id = cid
                    channel.save(update_fields=["youtube_channel_id", "updated_at"])
            if not cid:
                return Response({"detail": "Missing youtube_channel_id (and handle could not resolve)."}, status=status.HTTP_400_BAD_REQUEST)
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
                            "channel": channel,
                            "title": title or "",
                           "thumbnails": thumbs,
                            "item_count": count,
                        },
                    )
                    if was_created:
                        created += 1
                    else:
                        updated_count += 1
                page = data.get("nextPageToken")
                if not page:
                    break
            return Response({"created": created, "updated": updated_count})
        except youtube_api.YouTubeAPIError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="yt/sync-all")
    def sync_all(self, request, pk=None):
        """Sync playlists first, then videos for this channel in a single call.

        - Requires `onchannels.change_channel` permission.
        - If any playlists are active, videos are synced only for active playlists; otherwise all.
        """
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        playlists_created = 0
        playlists_updated = 0
        videos_created = 0
        videos_updated = 0
        try:
            # 1) Sync playlists (same logic as sync_playlists)
            cid = channel.youtube_channel_id
            if not cid and channel.youtube_handle:
                cid = youtube_api.resolve_channel_id(channel.youtube_handle)
                if cid and cid != channel.youtube_channel_id:
                    channel.youtube_channel_id = cid
                    channel.save(update_fields=["youtube_channel_id", "updated_at"])
            if not cid:
                return Response({"detail": "Missing youtube_channel_id (and handle could not resolve)."}, status=status.HTTP_400_BAD_REQUEST)
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
                            "channel": channel,
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

            # 2) Sync videos (same logic as sync_videos)
            from datetime import datetime, timezone

            playlists = list(channel.playlists.filter(is_active=True))
            if not playlists:
                playlists = list(channel.playlists.all())
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
                                "channel": channel,
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

            return Response({
                "playlists": {"created": playlists_created, "updated": playlists_updated},
                "videos": {"created": videos_created, "updated": videos_updated},
            })
        except youtube_api.YouTubeAPIError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    @swagger_auto_schema(
        manual_parameters=[
            PARAM_TENANT,
            PARAM_PLAYLIST_ID,
            PARAM_PLAYLIST_URL,
        ]
    )
    @action(detail=True, methods=["post"], url_path="yt/upsert-playlist")
    def upsert_playlist(self, request, pk=None):
        """Upsert a specific playlist into this channel by playlist_id or playlist_url."""
        # Require change permission explicitly
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        playlist_id = request.query_params.get("playlist_id") or request.data.get("playlist_id")
        playlist_url = request.query_params.get("playlist_url") or request.data.get("playlist_url")
        if not playlist_id and playlist_url:
            playlist_id = youtube_api.playlist_id_from_url(playlist_url)
        if not playlist_id:
            return Response({"detail": "Provide playlist_id or playlist_url."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            meta = youtube_api.get_playlist(playlist_id)
            obj, created = Playlist.objects.update_or_create(
                id=meta.get("id") or playlist_id,
                defaults={
                    "channel": channel,
                    "title": meta.get("title") or "",
                    "thumbnails": meta.get("thumbnails") or {},
                    "item_count": int(meta.get("itemCount") or 0),
                },
            )
            return Response({
                "id": obj.id,
                "title": obj.title,
                "channel": channel.id,
                "item_count": obj.item_count,
                "is_active": obj.is_active,
                "created": created,
            })
        except youtube_api.YouTubeAPIError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)

    @swagger_auto_schema(
        manual_parameters=[
            PARAM_TENANT,
            PARAM_PLAYLIST_ID,
            PARAM_PLAYLIST_URL,
            PARAM_PAGE_TOKEN,
            PARAM_MAX_RESULTS,
        ]
    )
    @action(detail=False, methods=["get"], url_path="yt/playlist-items")
    def yt_playlist_items(self, request):
        """List items for a playlist (?playlist_id=.. or ?playlist_url=..)."""
        # Accept playlist_id directly or a top-level 'list' (common when playlist_url isn't URL-encoded)
        playlist_id = request.query_params.get("playlist_id") or request.query_params.get("list")
        playlist_url = request.query_params.get("playlist_url")
        page_token = request.query_params.get("page_token")
        max_results = int(request.query_params.get("max_results", 25))
        if not playlist_id and playlist_url:
            # Extract list= parameter
            import urllib.parse as _up
            parsed = _up.urlparse(playlist_url)
            qs = _up.parse_qs(parsed.query)
            vals = qs.get("list")
            playlist_id = vals[0] if vals else None
        if not playlist_id:
            return Response({"detail": "Provide playlist_id or playlist_url."}, status=status.HTTP_400_BAD_REQUEST)
        try:
            data = youtube_api.list_playlist_items(playlist_id, page_token=page_token, max_results=max_results)
            return Response(data)
        except youtube_api.YouTubeAPIError as exc:
            return Response({"detail": str(exc)}, status=status.HTTP_502_BAD_GATEWAY)


class PlaylistViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Playlist.objects.select_related("channel").all()
    serializer_class = PlaylistSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["title", "id", "channel__id_slug"]
    ordering_fields = ["title", "last_synced_at", "item_count"]

    PARAM_TENANT = openapi.Parameter(
        name="X-Tenant-Id",
        in_=openapi.IN_HEADER,
        description="Tenant slug (e.g., ontime)",
        type=openapi.TYPE_STRING,
        required=True,
    )

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        # Enforce active-only for non-admins; allow admins to override via ?is_active=
        user = self.request.user
        if user.is_staff or user.has_perm("onchannels.change_channel"):
            is_active = self.request.query_params.get("is_active", "true")
            if is_active in {"true", "false", "1", "0"}:
                qs = qs.filter(is_active=is_active in {"true", "1"})
        else:
            qs = qs.filter(is_active=True)
        # Tenant filter (from header resolution middleware populates header)
        tenant = self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"
        qs = qs.filter(channel__tenant=tenant)
        # Optional channel filter by slug
        ch = self.request.query_params.get("channel")
        if ch:
            qs = qs.filter(channel__id_slug=ch)
        return qs


class VideoViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Video.objects.select_related("channel", "playlist").all()
    serializer_class = VideoSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["title", "video_id", "playlist__id", "channel__id_slug"]
    ordering_fields = ["published_at", "position", "last_synced_at"]

    PARAM_TENANT = openapi.Parameter(
        name="X-Tenant-Id",
        in_=openapi.IN_HEADER,
        description="Tenant slug (e.g., ontime)",
        type=openapi.TYPE_STRING,
        required=True,
    )

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        # Enforce active-only for non-admins; allow admins to override via ?is_active=
        user = self.request.user
        if user.is_staff or user.has_perm("onchannels.change_channel"):
            is_active = self.request.query_params.get("is_active", "true")
            if is_active in {"true", "false", "1", "0"}:
                qs = qs.filter(is_active=is_active in {"true", "1"})
        else:
            qs = qs.filter(is_active=True)
        tenant = self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"
        qs = qs.filter(channel__tenant=tenant)
        # Optional filters
        playlist_id = self.request.query_params.get("playlist")
        if playlist_id:
            qs = qs.filter(playlist__id=playlist_id)
        channel_slug = self.request.query_params.get("channel")
        if channel_slug:
            qs = qs.filter(channel__id_slug=channel_slug)
        return qs


class ShortsPlaylistsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"

        # Params
        updated_since_str = request.query_params.get("updated_since")
        try:
            if updated_since_str:
                since = datetime.fromisoformat(updated_since_str)
                if since.tzinfo is None:
                    since = since.replace(tzinfo=dt_timezone.utc)
            else:
                since = datetime.now(tz=dt_timezone.utc) - timedelta(days=int(request.query_params.get("days", 30)))
        except Exception:
            return Response({"detail": "Invalid updated_since"}, status=status.HTTP_400_BAD_REQUEST)

        limit = int(request.query_params.get("limit", 100))
        offset = int(request.query_params.get("offset", 0))
        per_channel_limit = int(request.query_params.get("per_channel_limit", 5))
        channel_slug = request.query_params.get("channel")

        qs = (
            Playlist.objects.select_related("channel")
            .filter(channel__tenant=tenant, is_active=True)
            .annotate(latest_video_published_at=Max("videos__published_at"))
        )

        # Filter only playlists explicitly marked as shorts
        qs = qs.filter(is_shorts=True)

        # Recency: include only if latest video is within the window
        qs = qs.filter(latest_video_published_at__gte=since)

        if channel_slug:
            qs = qs.filter(channel__id_slug=channel_slug)

        # Order by recency
        qs = qs.order_by("-latest_video_published_at", "-last_synced_at")

        # Apply per-channel limit in Python for portability
        items = []
        per_counts = {}
        for pl in qs:
            cid = pl.channel_id
            c = per_counts.get(cid, 0)
            if c < per_channel_limit:
                items.append(pl)
                per_counts[cid] = c + 1
            # Early exit if we have collected enough overall
            if len(items) >= offset + limit:
                break

        total = len(items)
        page = items[offset : offset + limit]
        ser = PlaylistSerializer(page, many=True, context={"request": request})
        return Response({"count": total, "results": ser.data})


class ShortsFeedView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"

        updated_since_str = request.query_params.get("updated_since")
        try:
            if updated_since_str:
                since = datetime.fromisoformat(updated_since_str)
                if since.tzinfo is None:
                    since = since.replace(tzinfo=dt_timezone.utc)
            else:
                since = datetime.now(tz=dt_timezone.utc) - timedelta(days=int(request.query_params.get("days", 30)))
        except Exception:
            return Response({"detail": "Invalid updated_since"}, status=status.HTTP_400_BAD_REQUEST)

        limit = int(request.query_params.get("limit", 100))
        per_channel_limit = int(request.query_params.get("per_channel_limit", 5))
        channel_slug = request.query_params.get("channel")
        bias_count = int(request.query_params.get("recent_bias_count", 20))

        qs = (
            Playlist.objects.select_related("channel")
            .filter(channel__tenant=tenant, is_active=True)
            .annotate(latest_video_published_at=Max("videos__published_at"))
        )

        qs = qs.filter(is_shorts=True)

        qs = qs.filter(Q(latest_video_published_at__gte=since) | Q(last_synced_at__gte=since))

        if channel_slug:
            qs = qs.filter(channel__id_slug=channel_slug)

        # Order by recency
        qs = qs.order_by("-latest_video_published_at", "-last_synced_at")

        # Apply per-channel limit in Python and cap total
        items = []
        per_counts = {}
        for pl in qs:
            cid = pl.channel_id
            c = per_counts.get(cid, 0)
            if c < per_channel_limit:
                items.append(pl)
                per_counts[cid] = c + 1
            if len(items) >= limit:
                break

        # Determine seed: explicit seed param, else X-Device-Id header, else user id
        seed = request.query_params.get("seed") or request.headers.get("X-Device-Id") or str(getattr(request.user, "id", "0"))
        seed_bytes = seed.encode("utf-8")
        seed_int = int.from_bytes(hashlib.sha256(seed_bytes).digest(), "big")

        # Bias: keep first bias_count in recency order; shuffle remainder deterministically
        head = items[:bias_count]
        tail = items[bias_count:]
        rng = random.Random(seed_int)
        rng.shuffle(tail)
        ordered = head + tail

        def normalize(pl: Playlist):
            updated_at = getattr(pl, "latest_video_published_at", None) or pl.last_synced_at
            return {
                "channel": pl.channel.id_slug,
                "playlist_id": pl.id,
                "title": pl.title,
                "updated_at": updated_at.isoformat() if updated_at else None,
                "items_count": pl.item_count,
            }

        results = [normalize(p) for p in ordered]
        return Response({"count": len(results), "results": results, "seed_source": "device"})


class ShortImportView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"
        data = request.data or {}
        ser = CreateShortJobSerializer(data=data)
        if not ser.is_valid():
            return Response(ser.errors, status=status.HTTP_400_BAD_REQUEST)
        payload = ser.validated_data
        # Basic preflight: require source_url
        source_url = payload.get('source_url')
        if not source_url:
            return Response({"detail": "source_url is required"}, status=status.HTTP_400_BAD_REQUEST)

        # Dedupe: find existing job by normalized video_id (fallback to url contains)
        vid = _yt_video_id_from_url(source_url) or _yt_video_id_via_ytdlp(source_url)
        base_qs = ShortJob.objects.filter(tenant=tenant).exclude(status=ShortJob.STATUS_DELETED)
        existing_ready = None
        existing_inprog = None
        if vid:
            existing_ready = base_qs.filter(status=ShortJob.STATUS_READY).filter(Q(source_url__icontains=vid)).order_by('-updated_at').first()
            if not existing_ready:
                existing_inprog = base_qs.filter(status__in=[ShortJob.STATUS_QUEUED, ShortJob.STATUS_DOWNLOADING, ShortJob.STATUS_TRANSCODING]).filter(Q(source_url__icontains=vid)).order_by('-updated_at').first()
        else:
            # Fallback: exact URL match
            existing_ready = base_qs.filter(status=ShortJob.STATUS_READY, source_url=source_url).first()
            if not existing_ready:
                existing_inprog = base_qs.filter(status__in=[ShortJob.STATUS_QUEUED, ShortJob.STATUS_DOWNLOADING, ShortJob.STATUS_TRANSCODING], source_url=source_url).first()

        if existing_ready:
            return Response({"job_id": str(existing_ready.id), "deduped": True, "status": existing_ready.status}, status=status.HTTP_200_OK)
        if existing_inprog:
            return Response({"job_id": str(existing_inprog.id), "deduped": True, "status": existing_inprog.status}, status=status.HTTP_202_ACCEPTED)

        job = ShortJob.objects.create(
            tenant=tenant,
            requested_by=getattr(request, 'user', None),
            source_url=source_url,
            status=ShortJob.STATUS_QUEUED,
            ladder_profile=payload.get('ladder_profile', 'shorts_v1'),
            content_class=payload.get('content_class', ShortJob.CLASS_NORMAL),
        )
        # Compute artifact prefix now for stable pathing
        job.artifact_prefix = f"shorts/{tenant}/{job.id}"
        job.save(update_fields=["artifact_prefix", "updated_at"])

        # Enqueue async processing
        try:
            from .tasks import process_short_job
            process_short_job.delay(str(job.id))
        except Exception:
            # If Celery unavailable, leave job queued; client can retry
            pass

        return Response({"job_id": str(job.id)}, status=status.HTTP_202_ACCEPTED)


class ShortImportStatusView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, job_id: str):
        job = ShortJob.objects.filter(id=job_id).first()
        if not job:
            return Response({"detail": "Not found"}, status=status.HTTP_404_NOT_FOUND)
        return Response(ShortJobSerializer(job).data)


class ShortImportRetryView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, job_id: str):
        job = ShortJob.objects.filter(id=job_id).first()
        if not job:
            return Response({"detail": "Not found"}, status=status.HTTP_404_NOT_FOUND)
        if job.status != ShortJob.STATUS_FAILED:
            return Response({"detail": "Only failed jobs can be retried."}, status=status.HTTP_400_BAD_REQUEST)
        # Reset and enqueue
        job.status = ShortJob.STATUS_QUEUED
        job.error_message = ""
        job.retry_count = (job.retry_count or 0) + 1
        job.save(update_fields=["status", "error_message", "retry_count", "updated_at"])
        try:
            from .tasks import process_short_job
            process_short_job.delay(str(job.id))
        except Exception:
            pass
        return Response({"job_id": str(job.id), "status": job.status})


class AdminShortsMetricsView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if not request.user.is_staff:
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"
        # Read metrics file
        media_root = Path(str(getattr(settings, 'MEDIA_ROOT', '/srv/media/short/videos')))
        metrics_path = media_root / 'shorts' / 'metrics.json'
        metrics = {}
        try:
            if metrics_path.exists():
                metrics = json.loads(metrics_path.read_text(encoding='utf-8'))
        except Exception:
            metrics = {}
        # Latest READY job for tenant
        latest = ShortJob.objects.filter(tenant=tenant, status=ShortJob.STATUS_READY).order_by('-updated_at').first()
        data = {
            'metrics': metrics,
            'latest_job_id': str(latest.id) if latest else None,
            'latest_hls': latest.hls_master_url if latest else None,
            'tenant': tenant,
        }
        return Response(data)


class ShortImportPreviewView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, job_id: str):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"
        job = ShortJob.objects.filter(id=job_id).first()
        if not job:
            return Response({"detail": "Not found"}, status=status.HTTP_404_NOT_FOUND)
        if job.tenant != tenant and not request.user.is_staff:
            return Response({"detail": "Wrong tenant"}, status=status.HTTP_403_FORBIDDEN)
        if job.status != ShortJob.STATUS_READY or not job.hls_master_url:
            return Response({"detail": "Not ready"}, status=status.HTTP_409_CONFLICT)

        master = job.hls_master_url
        signed = None
        if request.query_params.get('signed') in {'1', 'true', 'yes'}:
            try:
                exp = int((datetime.now(tz=dt_timezone.utc) + timedelta(minutes=10)).timestamp())
                msg = f"{master}:{exp}".encode('utf-8')
                key = (getattr(settings, 'SECRET_KEY', 'secret') or 'secret').encode('utf-8')
                sig = base64.urlsafe_b64encode(hmac.new(key, msg, digestmod='sha256').digest()).rstrip(b'=')
                sep = '&' if ('?' in master) else '?'
                signed = f"{master}{sep}exp={exp}&sig={sig.decode('utf-8')}"
            except Exception:
                signed = None
        return Response({"url": master, "signed_url": signed})


class ShortsBatchImportRecentView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"
        try:
            limit = int(request.query_params.get("limit", 10))
        except Exception:
            limit = 10
        # Find recent videos from active, shorts playlists for this tenant
        vids = (
            Video.objects.select_related("playlist", "channel")
            .filter(playlist__is_shorts=True, playlist__is_active=True, channel__tenant=tenant)
            .order_by("-published_at", "-position")[: max(1, min(limit, 50))]
        )
        results = []
        for v in vids:
            vid = v.video_id
            if not vid:
                continue
            source_url = f"https://youtu.be/{vid}"
            # Dedupe using existing helpers
            norm = _yt_video_id_from_url(source_url) or _yt_video_id_via_ytdlp(source_url)
            base_qs = ShortJob.objects.filter(tenant=tenant).exclude(status=ShortJob.STATUS_DELETED)
            existing_ready = None
            existing_inprog = None
            if norm:
                existing_ready = base_qs.filter(status=ShortJob.STATUS_READY, source_url__icontains=norm).order_by('-updated_at').first()
                if not existing_ready:
                    existing_inprog = base_qs.filter(status__in=[ShortJob.STATUS_QUEUED, ShortJob.STATUS_DOWNLOADING, ShortJob.STATUS_TRANSCODING], source_url__icontains=norm).order_by('-updated_at').first()
            if existing_ready:
                results.append({"video_id": vid, "job_id": str(existing_ready.id), "status": existing_ready.status, "deduped": True})
                continue
            if existing_inprog:
                results.append({"video_id": vid, "job_id": str(existing_inprog.id), "status": existing_inprog.status, "deduped": True})
                continue
            # Create new job (Ephemeral by default) and enqueue
            job = ShortJob.objects.create(
                tenant=tenant,
                requested_by=getattr(request, 'user', None),
                source_url=source_url,
                status=ShortJob.STATUS_QUEUED,
                ladder_profile='shorts_v1',
                content_class=getattr(ShortJob, 'CLASS_EPHEMERAL', 'ephemeral'),
            )
            job.artifact_prefix = f"shorts/{tenant}/{job.id}"
            job.save(update_fields=["artifact_prefix", "updated_at"])
            try:
                from .tasks import process_short_job
                process_short_job.delay(str(job.id))
            except Exception:
                pass
            results.append({"video_id": vid, "job_id": str(job.id), "status": job.status, "deduped": False})
        return Response({"count": len(results), "results": results})
