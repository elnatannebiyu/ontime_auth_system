from __future__ import annotations
from django.conf import settings
import os
from django.http import HttpResponse
from django.utils.html import escape
from rest_framework.views import APIView
from rest_framework import permissions
from pathlib import Path
import json

from .models import ShortJob


class AdminShortsMetricsHtmlView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        if not request.user.is_staff:
            return HttpResponse("Forbidden", status=403)
        tenant = request.headers.get("X-Tenant-Id") or request.GET.get("tenant") or "ontime"
        media_root = Path(str(getattr(settings, 'MEDIA_ROOT', '/srv/media/short/videos')))
        metrics_path = media_root / 'shorts' / 'metrics.json'
        metrics = {}
        try:
            if metrics_path.exists():
                metrics = json.loads(metrics_path.read_text(encoding='utf-8'))
        except Exception:
            metrics = {}
        latest = ShortJob.objects.filter(tenant=tenant, status=ShortJob.STATUS_READY).order_by('-updated_at').first()
        latest_hls = latest.hls_master_url if latest else None
        media_base = os.environ.get('MEDIA_PUBLIC_BASE', 'http://127.0.0.1:8080')
        abs_hls = f"{media_base}{latest_hls}" if latest_hls else None
        test_href = f"{media_base}/media/videos/hls_test.html?src={abs_hls}" if abs_hls else None
        metrics_pre = escape(json.dumps(metrics, indent=2))
        latest_hls_link = f"<a href='{escape(abs_hls)}'>{escape(abs_hls)}</a>" if abs_hls else "None"
        test_link = f"<div><a href='{escape(test_href)}'>Open in HLS Test Page</a></div>" if test_href else ""
        html = (
            "<!doctype html>"
            "<html><head><meta charset='utf-8'><title>Shorts Metrics</title>"
            "<meta name='viewport' content='width=device-width, initial-scale=1'>"
            "<style>body{font-family:-apple-system,Segoe UI,Roboto,Helvetica,Arial,sans-serif;margin:24px;background:#0b0c0f;color:#e6e9ef} .card{background:#111317;border:1px solid #2a2f3a;border-radius:10px;padding:16px;max-width:800px} a{color:#4ea1ff}</style>"
            "</head><body>"
            "<h1>Shorts Metrics</h1>"
            f"<div class='card'><pre>{metrics_pre}</pre></div>"
            "<h2>Latest READY</h2>"
            f"<div>Tenant: <strong>{escape(tenant)}</strong></div>"
            f"<div>Latest HLS: {latest_hls_link}</div>"
            f"{test_link}"
            "</body></html>"
        )
        return HttpResponse(html, content_type="text/html; charset=utf-8")
