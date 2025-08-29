from django.contrib import admin
from django.contrib.auth.models import Group, Permission

admin.site.unregister(Group)
@admin.register(Group)
class GroupAdmin(admin.ModelAdmin):
    filter_horizontal = ("permissions",)

@admin.register(Permission)
class PermissionAdmin(admin.ModelAdmin):
    list_display = ("name", "codename", "content_type")
    list_filter = ("content_type",)
