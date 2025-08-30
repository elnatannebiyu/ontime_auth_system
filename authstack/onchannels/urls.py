from rest_framework.routers import DefaultRouter
from .views import ChannelViewSet, PlaylistViewSet, VideoViewSet

router = DefaultRouter()
router.register(r"playlists", PlaylistViewSet, basename="playlist")
router.register(r"videos", VideoViewSet, basename="video")
router.register(r"", ChannelViewSet, basename="channel")

urlpatterns = router.urls
