from django.contrib import admin
from .models import Tenant, TenantDomain

@admin.register(Tenant)
class TenantAdmin(admin.ModelAdmin):
    list_display = ("slug", "name", "active")
    search_fields = ("slug", "name")

@admin.register(TenantDomain)
class TenantDomainAdmin(admin.ModelAdmin):
    list_display = ("domain", "tenant")
    search_fields = ("domain",)
