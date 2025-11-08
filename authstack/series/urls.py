from django.urls import path, include
from rest_framework.routers import DefaultRouter
from .views import ShowViewSet, SeasonViewSet, EpisodeViewSet, CategoryViewSet
from .views_tracking import ViewStartAPI, ViewHeartbeatAPI, ViewCompleteAPI

router = DefaultRouter()
router.register(r'shows', ShowViewSet, basename='series-shows')
router.register(r'seasons', SeasonViewSet, basename='series-seasons')
router.register(r'episodes', EpisodeViewSet, basename='series-episodes')
router.register(r'categories', CategoryViewSet, basename='series-categories')

urlpatterns = [
    path('', include(router.urls)),
    path('views/start', ViewStartAPI.as_view(), name='series-view-start'),
    path('views/heartbeat', ViewHeartbeatAPI.as_view(), name='series-view-heartbeat'),
    path('views/complete', ViewCompleteAPI.as_view(), name='series-view-complete'),
]
