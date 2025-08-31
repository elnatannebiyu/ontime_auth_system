from django.urls import path
from . import views

urlpatterns = [
    path('request/', views.request_otp_view, name='request_otp'),
    path('verify/', views.verify_otp_view, name='verify_otp'),
]
