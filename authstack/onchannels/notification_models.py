from django.db import models
from django.contrib.auth import get_user_model
from django.utils import timezone

User = get_user_model()


class Announcement(models.Model):
    KIND_FIRST_LOGIN = 'first_login'
    KIND_CHOICES = [
        (KIND_FIRST_LOGIN, 'First Login'),
    ]

    kind = models.CharField(max_length=32, choices=KIND_CHOICES, default=KIND_FIRST_LOGIN)
    title = models.CharField(max_length=200, blank=True, default='')
    body = models.TextField(blank=True, default='')

    # Optional tenant scoping (slug). Leave blank for global.
    tenant = models.CharField(max_length=64, blank=True, default='', help_text='Tenant slug (e.g., ontime). Leave blank for global')

    is_active = models.BooleanField(default=True)
    starts_at = models.DateTimeField(null=True, blank=True)
    ends_at = models.DateTimeField(null=True, blank=True)

    created_at = models.DateTimeField(auto_now_add=True)
    updated_at = models.DateTimeField(auto_now=True)

    class Meta:
        indexes = [
            models.Index(fields=['kind', 'tenant', 'is_active']),
            models.Index(fields=['starts_at']),
            models.Index(fields=['ends_at']),
        ]
        ordering = ['-updated_at']

    def is_current(self) -> bool:
        now = timezone.now()
        if not self.is_active:
            return False
        if self.starts_at and self.starts_at > now:
            return False
        if self.ends_at and self.ends_at < now:
            return False
        return True
