from django.urls import path
from .views import RegisterDeviceView, UnregisterDeviceView

urlpatterns = [
    path('register-device/', RegisterDeviceView.as_view(), name='register_device'),
    path('unregister-device/', UnregisterDeviceView.as_view(), name='unregister_device'),
]
