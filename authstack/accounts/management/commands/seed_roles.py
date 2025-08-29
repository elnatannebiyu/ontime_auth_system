from django.core.management.base import BaseCommand
from django.contrib.auth.models import Group, Permission
from django.apps import apps
from accounts.rolemap import ROLE_DEFS

class Command(BaseCommand):
    help = "Create default roles (groups) and assign permissions"

    def handle(self, *args, **kwargs):
        all_perms = list(Permission.objects.select_related("content_type"))

        for role, cfg in ROLE_DEFS.items():
            group, _ = Group.objects.get_or_create(name=role)
            group.permissions.clear()

            desired_perms = set()
            for pattern in cfg.get("permissions", []):
                if pattern.endswith("_*"):
                    prefix = pattern[:-2] + "_"
                    desired_perms.update([p for p in all_perms if p.codename.startswith(prefix)])
                else:
                    desired_perms.update([p for p in all_perms if p.codename == pattern])

            if desired_perms:
                group.permissions.add(*desired_perms)
                self.stdout.write(self.style.SUCCESS(f"Role '{role}': assigned {len(desired_perms)} perms"))
            else:
                self.stdout.write(self.style.WARNING(f"Role '{role}': no matching permissions found"))

        self.stdout.write(self.style.SUCCESS("Roles seeding complete."))
