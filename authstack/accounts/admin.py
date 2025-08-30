from django.contrib import admin
from django.contrib.auth.models import Group, Permission
from .models import UserSession, LoginAttempt, Membership

@admin.register(UserSession)
class UserSessionAdmin(admin.ModelAdmin):
    """Admin for managing user sessions"""
    list_display = ('user', 'device_type', 'ip_address', 'is_active', 'created_at', 
                    'last_activity', 'expires_at')
    list_filter = ('is_active', 'device_type', 'created_at')
    search_fields = ('user__username', 'user__email', 'ip_address', 'device_id')
    readonly_fields = ('id', 'device_id', 'refresh_token_jti', 'created_at')
    
    actions = ['revoke_sessions']
    
    def revoke_sessions(self, request, queryset):
        count = 0
        for session in queryset:
            if session.is_active:
                session.revoke('Admin action')
                count += 1
        self.message_user(request, f"Revoked {count} active sessions")
    revoke_sessions.short_description = "Revoke selected sessions"


@admin.register(LoginAttempt)
class LoginAttemptAdmin(admin.ModelAdmin):
    """Admin for viewing login attempts"""
    list_display = ('username', 'ip_address', 'success', 'timestamp', 'failure_reason')
    list_filter = ('success', 'timestamp', 'failure_reason')
    search_fields = ('username', 'ip_address')
    readonly_fields = ('username', 'ip_address', 'user_agent', 'success', 
                      'failure_reason', 'timestamp')
    
    def has_add_permission(self, request):
        return False  # Don't allow manual creation
    
    def has_change_permission(self, request, obj=None):
        return False  # Read-only


@admin.register(Membership)
class MembershipAdmin(admin.ModelAdmin):
    """Admin for tenant memberships"""
    list_display = ('user', 'tenant')
    list_filter = ('tenant',)
    search_fields = ('user__username', 'user__email', 'tenant__name')
    raw_id_fields = ('user',)


admin.site.unregister(Group)
@admin.register(Group)
class GroupAdmin(admin.ModelAdmin):
    filter_horizontal = ("permissions",)

@admin.register(Permission)
class PermissionAdmin(admin.ModelAdmin):
    list_display = ("name", "codename", "content_type")
    list_filter = ("content_type",)
