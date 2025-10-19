from rest_framework.routers import DefaultRouter
from django.urls import path
from .views import (
    LiveViewSet,
    LiveBySlugView,
    LivePreviewView,
    LiveProxyManifestView,
    LiveProxySegmentView,
)

router = DefaultRouter()
router.register(r"", LiveViewSet, basename="live")

urlpatterns = [
    # Fetch single live by channel slug
    path('<slug:slug>/', LiveBySlugView.as_view(), name='live-by-slug'),
    # Public preview page (no auth, requires is_previewable=True)
    path('preview/<slug:slug>/', LivePreviewView.as_view(), name='live-preview'),
    # Proxy endpoints for headers-injected playback (preview only)
    path('proxy/<slug:slug>/manifest/', LiveProxyManifestView.as_view(), name='live-proxy-manifest'),
    path('proxy/<slug:slug>/seg/<path:path>/', LiveProxySegmentView.as_view(), name='live-proxy-segment'),
]

urlpatterns += router.urls
