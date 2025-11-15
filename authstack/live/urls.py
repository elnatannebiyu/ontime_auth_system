from rest_framework.routers import DefaultRouter
from django.urls import path
from .views import (
    LiveViewSet,
    LiveRadioViewSet,
    LiveBySlugView,
    LivePreviewView,
    RadioListView,
    RadioBySlugView,
    RadioSearchView,
    RadioPreviewView,
    RadioPreviewStreamProxy,
    RadioStreamProxy,
    LiveListenStartView,
    LiveListenHeartbeatView,
    LiveListenStopView,
    RadioListenStartView,
    RadioListenHeartbeatView,
    RadioListenStopView,
)

router = DefaultRouter()
router.register(r"radios", LiveRadioViewSet, basename="live-radios")
router.register(r"", LiveViewSet, basename="live")

urlpatterns = [
    # Radio endpoints (specific routes)
    path('radio/', RadioListView.as_view(), name='radio-list'),
    path('radio/search/', RadioSearchView.as_view(), name='radio-search'),
    path('radio/preview/<slug:slug>/', RadioPreviewView.as_view(), name='radio-preview'),
    path('radio/preview/<slug:slug>/stream/', RadioPreviewStreamProxy.as_view(), name='radio-preview-stream'),
    path('radio/<slug:slug>/stream/', RadioStreamProxy.as_view(), name='radio-stream'),
    path('radio/<slug:slug>/listen/start/', RadioListenStartView.as_view(), name='radio-listen-start'),
    path('radio/<slug:slug>/listen/heartbeat/', RadioListenHeartbeatView.as_view(), name='radio-listen-heartbeat'),
    path('radio/<slug:slug>/listen/stop/', RadioListenStopView.as_view(), name='radio-listen-stop'),
    path('radio/<slug:slug>/', RadioBySlugView.as_view(), name='radio-detail'),

    # Live preview and listen endpoints
    path('preview/<slug:slug>/', LivePreviewView.as_view(), name='live-preview'),
    path('<slug:slug>/listen/start/', LiveListenStartView.as_view(), name='live-listen-start'),
    path('<slug:slug>/listen/heartbeat/', LiveListenHeartbeatView.as_view(), name='live-listen-heartbeat'),
    path('<slug:slug>/listen/stop/', LiveListenStopView.as_view(), name='live-listen-stop'),

    # Slug-based Live detail by channel slug (for app/frontend)
    path('by-channel/<slug:slug>/', LiveBySlugView.as_view(), name='live-by-channel'),
]

urlpatterns += router.urls
