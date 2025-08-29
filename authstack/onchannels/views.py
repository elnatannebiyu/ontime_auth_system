from rest_framework import viewsets, filters, permissions, status
from rest_framework.decorators import action
from rest_framework.response import Response

from .models import Channel, Playlist, Video
from .serializers import ChannelSerializer, PlaylistSerializer, VideoSerializer
from . import youtube_api
from drf_yasg import openapi
from drf_yasg.utils import swagger_auto_schema


class ChannelViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Channel.objects.all()
    serializer_class = ChannelSerializer
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
        # Optional filters
        is_active = self.request.query_params.get("is_active", "true")
        if is_active in {"true", "false", "1", "0"}:
            qs = qs.filter(is_active=is_active in {"true", "1"})
        tenant = self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"
        qs = qs.filter(tenant=tenant)
        return qs

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
    @action(detail=True, methods=["post"], url_path="yt/sync-videos")
    def sync_videos(self, request, pk=None):
        """Sync videos for this channel's active playlists (or all playlists if none active)."""
        if not request.user.has_perm("onchannels.change_channel"):
            return Response({"detail": "Permission denied."}, status=status.HTTP_403_FORBIDDEN)
        channel = self.get_object()
        try:
            playlists = list(channel.playlists.filter(is_active=True))
            if not playlists:
                playlists = list(channel.playlists.all())
            total_created = 0
            total_updated = 0
            from datetime import datetime, timezone
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
                                # YouTube returns e.g. 2020-01-01T12:34:56Z
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
                            total_created += 1
                        else:
                            total_updated += 1
                    page = data.get("nextPageToken")
                    if not page:
                        break
            return Response({"created": total_created, "updated": total_updated})
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
        # Default to active playlists unless explicitly overridden
        is_active = self.request.query_params.get("is_active", "true")
        if is_active in {"true", "false", "1", "0"}:
            qs = qs.filter(is_active=is_active in {"true", "1"})
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
        # Default to active
        is_active = self.request.query_params.get("is_active", "true")
        if is_active in {"true", "false", "1", "0"}:
            qs = qs.filter(is_active=is_active in {"true", "1"})
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
