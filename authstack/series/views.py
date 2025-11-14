from rest_framework import viewsets, permissions, filters, status
from rest_framework.decorators import action
from rest_framework.response import Response
from django.conf import settings
from django.db.models import Max, F, Count, Q
from django.utils import timezone
from django.core.management import call_command
from .models import Show, Season, Episode, Category
from .serializers import ShowSerializer, SeasonSerializer, EpisodeSerializer, CategoryListSerializer
import uuid


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


class ShowViewSet(viewsets.ModelViewSet):
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
        category_slug = self.request.query_params.get("category")
        if category_slug:
            qs = qs.filter(categories__slug=category_slug, categories__tenant=tenant, categories__is_active=True)
        # Optional flags for basic sections
        if self.request.query_params.get("trending"):
            try:
                days = int(self.request.query_params.get("days") or 7)
            except Exception:
                days = 7
            since = timezone.now() - timezone.timedelta(days=days)
            # Count EpisodeView rows per Show within the window
            qs = qs.annotate(
                recent_views=Count(
                    "seasons__episodes__views",
                    filter=Q(seasons__episodes__views__tenant=tenant, seasons__episodes__views__started_at__gte=since),
                    distinct=False,
                )
            ).order_by("-recent_views", "-updated_at")
        if self.request.query_params.get("new"):
            qs = qs.annotate(latest_time=Max("seasons__episodes__source_published_at")).order_by("-latest_time", "-updated_at")
        # Only active shows for non-admins
        if not (bool(getattr(self.request.user, 'is_superuser', False)) or self.request.user.has_perm("series.manage_content")):
            qs = qs.filter(is_active=True)
        return qs

    def tenant_slug(self):
        return self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy"}:
            return [permissions.IsAuthenticated(), permissions.DjangoModelPermissions()]
        return super().get_permissions()

    @swagger_auto_schema(manual_parameters=[BaseTenantReadOnlyViewSet.PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="sync-now")
    def sync_now(self, request, pk=None):
        """Run sync_season management command for this Season (fetch episodes).

        Mirrors the Django admin "Run sync now (fetch episodes)" action and
        returns a summary like "Sync complete. Succeeded: 1, Failed: 0".
        """
        season = self.get_object()
        tenant = self.tenant_slug()
        ref = f"{season.show.slug}:{season.number}"
        succeeded = 0
        failed = 0
        try:
            call_command("sync_season", ref, f"--tenant={tenant}")
            succeeded = 1
        except Exception as exc:  # noqa: BLE001
            failed = 1
            return Response(
                {
                    "detail": f"Sync failed for {ref}: {exc}",
                    "succeeded": succeeded,
                    "failed": failed,
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        msg = f"Sync complete. Succeeded: {succeeded}, Failed: {failed}"
        return Response({"detail": msg, "succeeded": succeeded, "failed": failed})

    def tenant_slug(self):
        return self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"

    def perform_create(self, serializer):
        tenant = self.tenant_slug()
        serializer.save(tenant=tenant)

    def perform_update(self, serializer):
        tenant = self.tenant_slug()
        serializer.save(tenant=tenant)

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy"}:
            return [permissions.IsAuthenticated(), permissions.DjangoModelPermissions()]
        return super().get_permissions()


class SeasonViewSet(viewsets.ModelViewSet):
    queryset = Season.objects.select_related("show").all()
    serializer_class = SeasonSerializer
    # Allow ordering and search by show slug/title and playlist id
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ["show__slug", "show__title", "yt_playlist_id"]
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
        if not (bool(getattr(self.request.user, 'is_superuser', False)) or self.request.user.has_perm("series.manage_content")):
            qs = qs.filter(is_enabled=True)
        return qs

    def tenant_slug(self):
        return self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"

    def perform_create(self, serializer):
        tenant = self.tenant_slug()
        show = serializer.validated_data.get("show")
        if show and show.tenant != tenant:
            raise PermissionError("Show belongs to a different tenant")
        serializer.save(tenant=tenant)

    def perform_update(self, serializer):
        tenant = self.tenant_slug()
        show = serializer.validated_data.get("show") or getattr(self.get_object(), "show", None)
        if show and show.tenant != tenant:
            raise PermissionError("Show belongs to a different tenant")
        serializer.save(tenant=tenant)

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy"}:
            return [permissions.IsAuthenticated(), permissions.DjangoModelPermissions()]
        return super().get_permissions()

    @swagger_auto_schema(manual_parameters=[BaseTenantReadOnlyViewSet.PARAM_TENANT])
    @action(detail=True, methods=["post"], url_path="sync-now")
    def sync_now(self, request, pk=None):
        """Run sync_season management command for this Season (fetch episodes).

        Mirrors the Django admin "Run sync now (fetch episodes)" action and
        returns a summary like "Sync complete. Succeeded: 1, Failed: 0".
        """
        season = self.get_object()
        tenant = self.tenant_slug()
        ref = f"{season.show.slug}:{season.number}"
        succeeded = 0
        failed = 0
        try:
            call_command("sync_season", ref, f"--tenant={tenant}")
            succeeded = 1
        except Exception as exc:  # noqa: BLE001
            failed = 1
            return Response(
                {
                    "detail": f"Sync failed for {ref}: {exc}",
                    "succeeded": succeeded,
                    "failed": failed,
                },
                status=status.HTTP_500_INTERNAL_SERVER_ERROR,
            )
        msg = f"Sync complete. Succeeded: {succeeded}, Failed: {failed}"
        return Response({"detail": msg, "succeeded": succeeded, "failed": failed})


class EpisodeViewSet(viewsets.ModelViewSet):
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
        if not (bool(getattr(self.request.user, 'is_superuser', False)) or self.request.user.has_perm("series.manage_content")):
            qs = qs.filter(visible=True, status=Episode.STATUS_PUBLISHED, season__is_enabled=True, season__show__is_active=True)
        # Default ordering: manual episode_number first (nulls last), then publish time, then id
        if not self.request.query_params.get("ordering"):
            try:
                qs = qs.order_by(F("episode_number").asc(nulls_last=True), "source_published_at", "id")
            except Exception:
                # Fallback for older DBs without nulls_last
                qs = qs.order_by("episode_number", "source_published_at", "id")
        return qs

    def tenant_slug(self):
        return self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy"}:
            return [permissions.IsAuthenticated(), permissions.DjangoModelPermissions()]
        return super().get_permissions()

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


class CategoryViewSet(viewsets.ModelViewSet):
    queryset = Category.objects.all()
    serializer_class = CategoryListSerializer
    filter_backends = [filters.OrderingFilter, filters.SearchFilter]
    ordering_fields = ["display_order", "name", "updated_at"]
    search_fields = ["name", "slug"]

    @swagger_auto_schema(manual_parameters=[BaseTenantReadOnlyViewSet.PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        tenant = self.tenant_slug()
        qs = qs.filter(tenant=tenant).order_by("display_order", "name")
        return qs

    def tenant_slug(self):
        return self.request.headers.get("X-Tenant-Id") or self.request.query_params.get("tenant") or "ontime"

    def perform_create(self, serializer):
        tenant = self.tenant_slug()
        serializer.save(tenant=tenant)

    def perform_update(self, serializer):
        tenant = self.tenant_slug()
        serializer.save(tenant=tenant)

    def get_permissions(self):
        if self.action in {"create", "update", "partial_update", "destroy"}:
            return [permissions.IsAuthenticated(), permissions.DjangoModelPermissions()]
        return super().get_permissions()
