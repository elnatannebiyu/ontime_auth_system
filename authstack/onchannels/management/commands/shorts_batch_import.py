from django.core.management.base import BaseCommand, CommandParser

from onchannels.tasks import select_and_enqueue_recent_shorts


class Command(BaseCommand):
    help = "Batch import recent shorts for a tenant (enqueue ShortJob tasks)."

    def add_arguments(self, parser: CommandParser) -> None:
        parser.add_argument("--tenant", type=str, default="ontime", help="Tenant id (default: ontime)")
        parser.add_argument("--limit", type=int, default=10, help="Max videos to import (1-50). Default 10")

    def handle(self, *args, **options):
        tenant: str = options.get("tenant") or "ontime"
        limit: int = int(options.get("limit") or 10)
        results = select_and_enqueue_recent_shorts(tenant=tenant, limit=limit)
        count = len(results)
        self.stdout.write(self.style.SUCCESS(f"Enqueued {count} short(s) for tenant='{tenant}'"))
        for it in results:
            status = it.get("status")
            vid = it.get("video_id")
            job_id = it.get("job_id")
            deduped = it.get("deduped")
            self.stdout.write(f" - video={vid} job={job_id} status={status} deduped={deduped}")
        return 0
