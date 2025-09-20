from rest_framework import viewsets, permissions, filters, status
from rest_framework.decorators import action
from rest_framework.response import Response
from drf_yasg import openapi
from drf_yasg.utils import swagger_auto_schema

from .models import Show, Season, Episode
from .serializers import ShowSerializer, SeasonSerializer, EpisodeSerializer
from django.db.models import F
import uuid


class BaseTenantReadOnlyViewSet(viewsets.ReadOnlyModelViewSet):
    permission_classes = [permissions.IsAuthenticated]

    PARAM_TENANT = openapi.Parameter(
        name="X-Tenant-Id",
        in_=openapi.IN_HEADER,
        description="Tenant slug (e.g., ontime)",
        type=openapi.TYPE_STRING,
        required=True,
    )

    def tenant_slug(self):
        return self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"


class ShowViewSet(BaseTenantReadOnlyViewSet):
    queryset = Show.objects.select_related("channel").all()
    serializer_class = ShowSerializer
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["slug", "title"]
    ordering_fields = ["title", "updated_at"]
    lookup_field = "slug"

    @swagger_auto_schema(manual_parameters=[BaseTenantReadOnlyViewSet.PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        tenant = self.tenant_slug()
        qs = qs.filter(tenant=tenant)
        # Only active shows for non-admins
        if not (self.request.user.is_staff or self.request.user.has_perm("series.manage_content")):
            qs = qs.filter(is_active=True)
        return qs


class SeasonViewSet(BaseTenantReadOnlyViewSet):
    queryset = Season.objects.select_related("show").all()
    serializer_class = SeasonSerializer
    filter_backends = [filters.OrderingFilter]
    ordering_fields = ["number", "updated_at"]

    @swagger_auto_schema(manual_parameters=[BaseTenantReadOnlyViewSet.PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        tenant = self.tenant_slug()
        qs = qs.filter(tenant=tenant, show__tenant=tenant)
        show_slug = self.request.query_params.get("show")
        if show_slug:
            qs = qs.filter(show__slug=show_slug)
        # Only enabled seasons for non-admins
        if not (self.request.user.is_staff or self.request.user.has_perm("series.manage_content")):
            qs = qs.filter(is_enabled=True)
        return qs


class EpisodeViewSet(BaseTenantReadOnlyViewSet):
    queryset = Episode.objects.select_related("season", "season__show").all()
    serializer_class = EpisodeSerializer
    filter_backends = [filters.OrderingFilter]
    ordering_fields = ["episode_number", "source_published_at", "updated_at"]

    @swagger_auto_schema(manual_parameters=[BaseTenantReadOnlyViewSet.PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        tenant = self.tenant_slug()
        qs = qs.filter(tenant=tenant, season__tenant=tenant, season__show__tenant=tenant)
        season_id = self.request.query_params.get("season")
        if season_id:
            qs = qs.filter(season__id=season_id)
        # Public filter: only visible published episodes unless admin
        if not (self.request.user.is_staff or self.request.user.has_perm("series.manage_content")):
            qs = qs.filter(visible=True, status=Episode.STATUS_PUBLISHED, season__is_enabled=True, season__show__is_active=True)
        # Default ordering: manual episode_number first (nulls last), then publish time, then id
        if not self.request.query_params.get("ordering"):
            try:
                qs = qs.order_by(F("episode_number").asc(nulls_last=True), "source_published_at", "id")
            except Exception:
                # Fallback for older DBs without nulls_last
                qs = qs.order_by("episode_number", "source_published_at", "id")
        return qs

    @swagger_auto_schema(manual_parameters=[BaseTenantReadOnlyViewSet.PARAM_TENANT])
    @action(detail=True, methods=["get"], url_path="play")
    def play(self, request, pk=None):
        """Return safe playback config (never full YouTube URL)."""
        ep = self.get_object()
        # Generate a short-lived playback token (client echoes it in view tracking)
        playback_token = uuid.uuid4().hex
        return Response({
            "episode_id": ep.id,
            "video_id": ep.source_video_id,
            "playback_token": playback_token,
            "player_params": {"start": 0},
        }, status=status.HTTP_200_OK)
