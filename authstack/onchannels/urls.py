from rest_framework.routers import DefaultRouter
from django.urls import path
from .views import ChannelViewSet, PlaylistViewSet, VideoViewSet
from . import version_views
from .notifications_views import (
    list_notifications_view,
    mark_read_view,
    mark_all_read_view,
)

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
    # Notifications
    path('notifications/', list_notifications_view, name='list_notifications'),
    path('notifications/mark-read/', mark_read_view, name='mark_read_notifications'),
    path('notifications/mark-all-read/', mark_all_read_view, name='mark_all_read_notifications'),
    # Announcements
    path('announcements/first-login/', version_views.first_login_announcement_view, name='first_login_announcement'),
]

urlpatterns += router.urls
