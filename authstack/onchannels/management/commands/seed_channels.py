import json
import sys
from pathlib import Path
from typing import Dict, Any, List, Tuple, Set

from django.core.management.base import BaseCommand, CommandError
from django.db import transaction
from django.conf import settings

from onchannels.models import Channel


def _read_json(path: Path) -> Dict[str, Any]:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def _map_channel_payload(payload: Dict[str, Any]) -> Dict[str, Any]:
    # Defensive reads with defaults
    display = payload.get("display", {}) or {}
    categorization = payload.get("categorization", {}) or {}
    availability = payload.get("availability", {}) or {}
    lineup = payload.get("lineup", {}) or {}

    data: Dict[str, Any] = {
        "tenant": payload.get("tenant") or "ontime",
        "id_slug": payload.get("id") or "",
        "default_locale": display.get("default_locale") or "am",
        "name_am": (display.get("name") or {}).get("am"),
        "name_en": (display.get("name") or {}).get("en"),
        "aliases": display.get("aliases") or [],
        "images": payload.get("images") or [],
        "sources": payload.get("sources") or [],
        "genres": categorization.get("genres") or [],
        "language": categorization.get("language") or "am",
        "country": categorization.get("country") or "ET",
        "tags": categorization.get("tags") or [],
        "is_active": availability.get("is_active", True),
        "platforms": availability.get("platforms") or [],
        "drm_required": availability.get("drm_required", False),
        "sort_order": lineup.get("sort_order", 100),
        "featured": lineup.get("featured", False),
        "rights": payload.get("rights") or {},
        "audit": payload.get("audit") or {},
    }
    if not data["id_slug"]:
        raise ValueError("Missing required 'id' field in payload")
    return data


class Command(BaseCommand):
    help = "Seed/update Channel rows from channel.v1.json files"

    def add_arguments(self, parser):
        parser.add_argument(
            "--path",
            dest="path",
            default=str(Path(settings.BASE_DIR) / "youtube_channels"),
            help="Directory containing per-channel folders with channel.v1.json",
        )
        parser.add_argument(
            "--tenant",
            dest="tenant",
            default=None,
            help="Restrict seeding to a specific tenant (default: use value in file)",
        )
        parser.add_argument(
            "--dry-run",
            action="store_true",
            help="Parse and report without writing to the database",
        )
        parser.add_argument(
            "--deactivate-missing",
            action="store_true",
            help="Deactivate channels in DB that are not present in the source files (scoped by tenant)",
        )
        parser.add_argument(
            "--verbose-files",
            action="store_true",
            help="Print each processed file path",
        )

    def handle(self, *args, **options):
        base_path = Path(options["path"]).resolve()
        tenant_override = options.get("tenant")
        dry_run: bool = options.get("dry_run", False)
        deactivate_missing: bool = options.get("deactivate_missing", False)
        verbose_files: bool = options.get("verbose_files", False)

        if not base_path.exists() or not base_path.is_dir():
            raise CommandError(f"Path not found or not a directory: {base_path}")

        # Discover files: */channel.v1.json under base_path
        files: List[Path] = []
        for child in base_path.iterdir():
            if child.is_dir():
                json_path = child / "channel.v1.json"
                if json_path.exists():
                    files.append(json_path)
        if not files:
            self.stdout.write(self.style.WARNING("No channel.v1.json files found."))
            return

        upserts = 0
        created = 0
        updated = 0
        errors: List[Tuple[Path, str]] = []

        seen_keys: Set[Tuple[str, str]] = set()  # (tenant, id_slug)

        def _apply_row(data: Dict[str, Any]) -> Tuple[bool, Channel]:
            nonlocal created, updated, upserts
            tenant = data["tenant"]
            id_slug = data["id_slug"]
            obj, was_created = Channel.objects.update_or_create(
                tenant=tenant,
                id_slug=id_slug,
                defaults=data,
            )
            upserts += 1
            if was_created:
                created += 1
            else:
                updated += 1
            return was_created, obj

        # Process files
        for path in files:
            try:
                if verbose_files:
                    self.stdout.write(f"Processing: {path}")
                payload = _read_json(path)
                data = _map_channel_payload(payload)
                if tenant_override:
                    data["tenant"] = tenant_override
                seen_keys.add((data["tenant"], data["id_slug"]))
                if dry_run:
                    # Validate mapping only
                    continue
                _apply_row(data)
            except Exception as exc:  # noqa: BLE001
                errors.append((path, str(exc)))

        # Deactivate missing
        deactivated = 0
        if not dry_run and deactivate_missing:
            tenants_in_scope = {tenant_override} if tenant_override else {t for (t, _) in seen_keys}
            for tenant in tenants_in_scope:
                db_keys = set(Channel.objects.filter(tenant=tenant).values_list("tenant", "id_slug"))
                missing = db_keys - seen_keys
                if missing:
                    q = Channel.objects.filter(tenant=tenant, id_slug__in=[k[1] for k in missing])
                    deactivated += q.update(is_active=False)

        # Report
        self.stdout.write(self.style.SUCCESS(
            f"Seed complete. files={len(files)} upserts={upserts} created={created} updated={updated} "
            f"deactivated={deactivated} errors={len(errors)}"
        ))
        if errors:
            for path, err in errors[:20]:
                self.stdout.write(self.style.ERROR(f"Error: {path}: {err}"))
            if len(errors) > 20:
                self.stdout.write(self.style.ERROR(f"... and {len(errors) - 20} more errors"))
        if dry_run and errors:
            # Non-fatal in dry run
            return
        if errors and not dry_run:
            # Non-zero exit code to flag issues in CI/scripts
            raise CommandError(f"Encountered {len(errors)} errors while seeding.")
