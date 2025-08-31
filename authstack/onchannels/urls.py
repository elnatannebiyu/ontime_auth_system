from rest_framework.routers import DefaultRouter
from django.urls import path
from .views import ChannelViewSet, PlaylistViewSet, VideoViewSet
from . import version_views

router = DefaultRouter()
router.register(r"playlists", PlaylistViewSet, basename="playlist")
router.register(r"videos", VideoViewSet, basename="video")
router.register(r"", ChannelViewSet, basename="channel")

urlpatterns = [
    # Version endpoints
    path('version/check/', version_views.check_version_view, name='check_version'),
    path('version/latest/', version_views.get_latest_version_view, name='latest_version'),
    path('version/supported/', version_views.get_supported_versions_view, name='supported_versions'),
    path('features/', version_views.get_feature_flags_view, name='feature_flags'),
]

urlpatterns += router.urls
