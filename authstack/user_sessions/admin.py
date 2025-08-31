from django.contrib import admin
from django.utils import timezone
from .models import Session, Device

@admin.register(Session)
class SessionAdmin(admin.ModelAdmin):
    """Admin for refresh token sessions"""
    list_display = ('user', 'device', 'rotation_counter', 'created_at')
    list_filter = ('created_at',)
    search_fields = ('user__username', 'user__email')
    readonly_fields = ('id', 'refresh_token_family', 'created_at')

@admin.register(Device)
class DeviceAdmin(admin.ModelAdmin):
    """Admin for user devices"""
    list_display = ('user', 'device_name', 'device_type', 'last_seen_at')
    list_filter = ('device_type', 'last_seen_at')
    search_fields = ('user__username', 'user__email', 'device_id', 'device_name')
    readonly_fields = ('id', 'device_id', 'created_at')
