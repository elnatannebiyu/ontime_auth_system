from django.db import models


class Tenant(models.Model):
    slug = models.SlugField(max_length=64, unique=True)
    name = models.CharField(max_length=128)
    active = models.BooleanField(default=True)

    def __str__(self) -> str:
        return self.slug


class TenantDomain(models.Model):
    tenant = models.ForeignKey(Tenant, on_delete=models.CASCADE, related_name="domains")
    domain = models.CharField(max_length=255, unique=True)

    def __str__(self) -> str:
        return f"{self.domain} -> {self.tenant.slug}"
