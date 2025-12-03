from django.contrib import admin
from django.contrib.auth.models import Group, Permission
from django.contrib.auth import get_user_model
from django.contrib.auth.admin import UserAdmin as DjangoUserAdmin
from .models import UserSession, LoginAttempt, Membership, UserProfile
from common.fcm_sender import send_to_user

@admin.register(UserSession)
class UserSessionAdmin(admin.ModelAdmin):
    """Admin for managing user sessions"""
    list_display = (
        'user', 'device_type', 'os_name', 'os_version', 'ip_address',
        'is_active', 'created_at', 'last_activity', 'expires_at'
    )
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
    """Admin for tenant memberships, showing per-tenant roles and their permissions."""
    list_display = ('user', 'tenant', 'roles_list')
    list_filter = ('tenant',)
    search_fields = ('user__username', 'user__email', 'tenant__name')
    raw_id_fields = ('user',)
    filter_horizontal = ('roles',)
    readonly_fields = ('roles_list', 'role_permissions')

    def roles_list(self, obj):
        return ", ".join(obj.roles.values_list('name', flat=True)) or '(none)'
    roles_list.short_description = 'Roles'

    def role_permissions(self, obj):
        from django.contrib.auth.models import Permission
        perms = Permission.objects.filter(group__in=obj.roles.all()).values_list(
            'content_type__app_label', 'codename'
        )
        # Display as app_label.codename lines
        lines = [f"{app}.{code}" for app, code in perms]
        return "\n".join(sorted(lines)) or '(none)'
    role_permissions.short_description = 'Role permissions (app.codename)'


admin.site.unregister(Group)
@admin.register(Group)
class GroupAdmin(admin.ModelAdmin):
    filter_horizontal = ("permissions",)

@admin.register(Permission)
class PermissionAdmin(admin.ModelAdmin):
    list_display = ("name", "codename", "content_type")
    list_filter = ("content_type",)


User = get_user_model()


class UserProfileInline(admin.StackedInline):
    model = UserProfile
    can_delete = False
    extra = 0
    fk_name = "user"
    fields = ("email_verified",)


try:
    admin.site.unregister(User)
except Exception:
    pass

@admin.register(User)
class UserAdmin(DjangoUserAdmin):
    actions = ['send_test_push']
    inlines = [UserProfileInline]

    def send_test_push(self, request, queryset):
        title = "Test push"
        body = "Hello from Admin"
        total_ok = 0
        total_bad = 0
        for user in queryset:
            try:
                ok, bad = send_to_user(user_id=user.id, title=title, body=body, data={"link": "/inbox"})
                total_ok += len(ok)
                total_bad += len(bad)
            except Exception as exc:  # noqa: BLE001
                self.message_user(request, f"Failed to send to user {user.id}: {exc}", level='error')
        self.message_user(request, f"Sent to {total_ok} token(s); failed {total_bad}.")
    send_test_push.short_description = "Send test push to selected users"
