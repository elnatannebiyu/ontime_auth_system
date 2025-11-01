from rest_framework.routers import DefaultRouter
from django.urls import path
from .views import (
    ChannelViewSet, PlaylistViewSet, VideoViewSet,
    ShortsPlaylistsView, ShortsFeedView,
    ShortImportView, ShortImportStatusView, ShortImportRetryView, ShortImportPreviewView, ShortsBatchImportRecentView, ShortsReadyView, ShortsReadyFeedView,
    ShortsReactionView, ShortsCommentsView, ShortsCommentDetailView, ShortsSearchView,
    AdminShortsMetricsView,
)
from .admin_views import AdminShortsMetricsHtmlView
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
    # Shorts endpoints
    path('shorts/playlists/', ShortsPlaylistsView.as_view(), name='shorts_playlists'),
    path('shorts/feed/', ShortsFeedView.as_view(), name='shorts_feed'),
    path('shorts/import/', ShortImportView.as_view(), name='shorts_import'),
    path('shorts/import/<uuid:job_id>/', ShortImportStatusView.as_view(), name='shorts_import_status'),
    path('shorts/import/<uuid:job_id>/preview/', ShortImportPreviewView.as_view(), name='shorts_import_preview'),
    path('shorts/import/<uuid:job_id>/retry/', ShortImportRetryView.as_view(), name='shorts_import_retry'),
    path('shorts/import/batch/recent/', ShortsBatchImportRecentView.as_view(), name='shorts_import_batch_recent'),
    path('shorts/ready/', ShortsReadyView.as_view(), name='shorts_ready'),
    path('shorts/ready/feed/', ShortsReadyFeedView.as_view(), name='shorts_ready_feed'),
    # Shorts social/search
    path('shorts/<uuid:job_id>/reaction/', ShortsReactionView.as_view(), name='shorts_reaction'),
    path('shorts/<uuid:job_id>/comments/', ShortsCommentsView.as_view(), name='shorts_comments'),
    path('shorts/comments/<int:comment_id>/', ShortsCommentDetailView.as_view(), name='shorts_comment_detail'),
    path('shorts/search/', ShortsSearchView.as_view(), name='shorts_search'),
    # Admin metrics (staff only)
    path('shorts/admin/metrics/', AdminShortsMetricsView.as_view(), name='shorts_admin_metrics'),
    path('shorts/admin/metrics/html/', AdminShortsMetricsHtmlView.as_view(), name='shorts_admin_metrics_html'),
    # Notifications
    path('notifications/', list_notifications_view, name='list_notifications'),
    path('notifications/mark-read/', mark_read_view, name='mark_read_notifications'),
    path('notifications/mark-all-read/', mark_all_read_view, name='mark_all_read_notifications'),
    # Announcements
    path('announcements/first-login/', version_views.first_login_announcement_view, name='first_login_announcement'),
]

urlpatterns += router.urls
