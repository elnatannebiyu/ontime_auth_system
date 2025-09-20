from rest_framework import views, permissions, status
from rest_framework.response import Response
from django.utils import timezone
from django.db import transaction

from .models import Episode, EpisodeView


class ViewStartAPI(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"
        data = request.data or {}
        episode_id = data.get("episode_id")
        playback_token = (data.get("playback_token") or "").strip()
        started_at = data.get("started_at")  # optional ISO string
        device_id = (data.get("device_id") or "").strip()

        if not episode_id:
            return Response({"error": "episode_id is required"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            ep = Episode.objects.get(id=episode_id, tenant=tenant, season__tenant=tenant)
        except Episode.DoesNotExist:
            return Response({"error": "Episode not found for tenant"}, status=status.HTTP_404_NOT_FOUND)

        # Parse started_at if provided
        ts = timezone.now()
        try:
            if started_at:
                ts = timezone.make_aware(timezone.datetime.fromisoformat(started_at.replace("Z", "+00:00")))
        except Exception:
            ts = timezone.now()

        # Store view row
        ev = EpisodeView(
            tenant=tenant,
            episode=ep,
            user=request.user if request.user.is_authenticated else None,
            session_id=request.headers.get("X-Session-Id", ""),
            device_id=device_id,
            source_provider="youtube",
            playback_token=playback_token,
            started_at=ts,
            ip=request.META.get("REMOTE_ADDR"),
            user_agent=request.META.get("HTTP_USER_AGENT", ""),
        )
        ev.save()
        return Response({"view_id": ev.id}, status=status.HTTP_201_CREATED)


class ViewHeartbeatAPI(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"
        data = request.data or {}
        view_id = data.get("view_id")
        playback_token = (data.get("playback_token") or "").strip()
        seconds_watched = int(data.get("seconds_watched") or 0)
        # Optional fields (not strictly used server-side yet)
        _player_state = data.get("player_state")
        _pos = data.get("position_seconds")

        if not view_id:
            return Response({"error": "view_id is required"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            ev = EpisodeView.objects.select_for_update().get(id=view_id, tenant=tenant)
        except EpisodeView.DoesNotExist:
            return Response({"error": "View not found for tenant"}, status=status.HTTP_404_NOT_FOUND)

        # Basic token check (best-effort for v1)
        if playback_token and ev.playback_token and playback_token != ev.playback_token:
            return Response({"error": "Invalid playback token"}, status=status.HTTP_400_BAD_REQUEST)

        # Clamp seconds to avoid abuse
        seconds_watched = max(0, min(120, seconds_watched))
        ev.total_seconds = max(0, ev.total_seconds + seconds_watched)
        ev.last_heartbeat_at = timezone.now()
        ev.save(update_fields=["total_seconds", "last_heartbeat_at", "updated_at"])
        return Response({"ok": True}, status=status.HTTP_200_OK)


class ViewCompleteAPI(views.APIView):
    permission_classes = [permissions.IsAuthenticated]

    @transaction.atomic
    def post(self, request):
        tenant = request.headers.get("X-Tenant-Id") or request.query_params.get("tenant") or "ontime"
        data = request.data or {}
        view_id = data.get("view_id")
        playback_token = (data.get("playback_token") or "").strip()
        total_seconds = int(data.get("total_seconds") or 0)
        completed = bool(data.get("completed") or True)

        if not view_id:
            return Response({"error": "view_id is required"}, status=status.HTTP_400_BAD_REQUEST)
        try:
            ev = EpisodeView.objects.select_for_update().get(id=view_id, tenant=tenant)
        except EpisodeView.DoesNotExist:
            return Response({"error": "View not found for tenant"}, status=status.HTTP_404_NOT_FOUND)

        if playback_token and ev.playback_token and playback_token != ev.playback_token:
            return Response({"error": "Invalid playback token"}, status=status.HTTP_400_BAD_REQUEST)

        # Keep the larger of previously accumulated and the provided value
        total_seconds = max(0, total_seconds)
        ev.total_seconds = max(ev.total_seconds, total_seconds)
        if completed:
            ev.completed = True
        ev.last_heartbeat_at = timezone.now()
        ev.save(update_fields=["total_seconds", "completed", "last_heartbeat_at", "updated_at"])
        return Response({"ok": True}, status=status.HTTP_200_OK)
