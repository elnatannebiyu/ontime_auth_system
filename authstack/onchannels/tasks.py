from __future__ import annotations
import logging
from typing import List
from django.utils import timezone
from django.db import transaction
from celery import shared_task
import subprocess
import tempfile
import shutil
from pathlib import Path
import os
import json

from django.conf import settings
import time

from onchannels.models import ScheduledNotification, ShortJob, Video, Playlist
from user_sessions.models import Device
from common.fcm_sender import send_to_token, send_to_topic

logger = logging.getLogger("shorts.ingest")

# Module-level helpers needed by multiple tasks
def _parse_cap_env(name: str, default_bytes: int) -> int:
    try:
        val = os.environ.get(name)
        if not val:
            return default_bytes
        val = val.strip().lower()
        mul = 1
        if val.endswith('gb'):
            mul = 1024**3
            val = val[:-2]
        elif val.endswith('mb'):
            mul = 1024**2
            val = val[:-2]
        elif val.endswith('kb'):
            mul = 1024
            val = val[:-2]
        return int(float(val) * mul)
    except Exception:
        return default_bytes


def _tenant_caps(tenant: str) -> tuple[int, int]:
    # Per-tenant env override, else global tenant defaults
    tkey = (tenant or '').strip().upper().replace('-', '_')
    soft = _parse_cap_env(f'SHORTS_TENANT_{tkey}_SOFT', _parse_cap_env('SHORTS_TENANT_SOFT', 3 * 1024**3))
    hard = _parse_cap_env(f'SHORTS_TENANT_{tkey}_HARD', _parse_cap_env('SHORTS_TENANT_HARD', 4 * 1024**3))
    return soft, hard

@shared_task(bind=True, autoretry_for=(Exception,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def enqueue_notification(self, notification_id: int) -> bool:
    # Idempotency guard: lock the row and only send if still pending
    with transaction.atomic():
        n = ScheduledNotification.objects.select_for_update(skip_locked=True).filter(id=notification_id).first()
        if not n:
            return False
        if n.status != ScheduledNotification.STATUS_PENDING:
            return False
        # proceed to dispatch while holding the lock
        result = _dispatch_single(n)
    return result


def _dispatch_single(n: ScheduledNotification) -> bool:
    try:
        # Optional delivery hints
        ttl = None
        collapse = None
        try:
            if isinstance(n.data, dict):
                ttl = n.data.get('_ttl')
                collapse = n.data.get('_collapse') or n.data.get('_collapse_key')
                if isinstance(ttl, str) and ttl.isdigit():
                    ttl = int(ttl)
        except Exception:
            ttl = None
            collapse = None

        if n.target_type == ScheduledNotification.TARGET_TOKEN:
            if not n.target_value:
                raise ValueError("Missing target_value for token notification")
            send_to_token(n.title, n.body, n.target_value, (n.data or {}), ttl_seconds=ttl, collapse_key=collapse)
            _mark_sent(n)
            return True
        elif n.target_type == ScheduledNotification.TARGET_TOPIC:
            if not n.target_value:
                raise ValueError("Missing target_value (topic)")
            send_to_topic(n.title, n.body, n.target_value, (n.data or {}), ttl_seconds=ttl, collapse_key=collapse)
            _mark_sent(n)
            return True
        elif n.target_type == ScheduledNotification.TARGET_USER:
            if not n.target_user_id:
                raise ValueError("Missing target_user for user notification")
            devices: List[Device] = list(Device.objects.filter(user_id=n.target_user_id, push_enabled=True).exclude(push_token="").all())
            if not devices:
                raise ValueError("No devices with push_token for target user")
            for d in devices:
                if not d.push_token:
                    continue
                try:
                    send_to_token(n.title, n.body, d.push_token, (n.data or {}), ttl_seconds=ttl, collapse_key=collapse)
                except Exception as exc:
                    # Log but continue with other devices
                    _set_error(n, f"Device {d.id}: {exc}")
            _mark_sent(n)
            return True
        else:
            raise ValueError(f"Unknown target_type: {n.target_type}")
    except Exception as exc:
        _record_failure(n, str(exc))
        raise


def _mark_sent(n: ScheduledNotification) -> None:
    n.status = ScheduledNotification.STATUS_SENT
    n.attempts = (n.attempts or 0) + 1
    n.last_error = ""
    n.save(update_fields=["status", "attempts", "last_error", "updated_at"])


def _record_failure(n: ScheduledNotification, error: str) -> None:
    n.status = ScheduledNotification.STATUS_FAILED
    n.attempts = (n.attempts or 0) + 1
    n.last_error = (error or "")[:1000]
    n.save(update_fields=["status", "attempts", "last_error", "updated_at"])


@shared_task(bind=True)
def dispatch_due_notifications(self) -> int:
    now = timezone.now()
    due = list(ScheduledNotification.objects.select_for_update(skip_locked=True).filter(status=ScheduledNotification.STATUS_PENDING, send_at__lte=now)[:50])
    count = 0
    if not due:
        return 0
    with transaction.atomic():
        for n in due:
            # Re-fetch locked row in transaction to avoid double-send
            n = ScheduledNotification.objects.select_for_update().get(pk=n.pk)
            if not n.is_due():
                continue
            try:
                _dispatch_single(n)
                count += 1
            except Exception:
                # failure recorded inside _dispatch_single
                continue
    return count


# Error classes for retry policy
class TransientError(Exception):
    pass


class PermanentError(Exception):
    pass


@shared_task(bind=True, autoretry_for=(TransientError,), retry_backoff=True, retry_kwargs={"max_retries": 3})
def process_short_job(self, job_id: str) -> bool:
    job = ShortJob.objects.filter(id=job_id).first()
    if not job:
        return False
    t_job_start = time.monotonic()
    logger.info("shortjob.start", extra={"job_id": str(job_id), "tenant": getattr(job, 'tenant', None)})

    def _run(cmd: list[str], cwd: Path | None = None) -> None:
        proc = subprocess.run(cmd, cwd=str(cwd) if cwd else None, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if proc.returncode != 0:
            raise RuntimeError(f"Command failed: {' '.join(cmd)}\nSTDOUT:\n{proc.stdout}\nSTDERR:\n{proc.stderr}")

    def _ffprobe_duration(path: Path) -> float:
        cmd = [
            'ffprobe', '-v', 'error', '-show_entries', 'format=duration', '-of', 'default=noprint_wrappers=1:nokey=1', str(path)
        ]
        proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        if proc.returncode != 0:
            raise RuntimeError(f"ffprobe failed: {proc.stderr}")
        try:
            return float(proc.stdout.strip())
        except Exception:
            return 0.0

    def _parse_cap_env(name: str, default_bytes: int) -> int:
        try:
            val = os.environ.get(name)
            if not val:
                return default_bytes
            val = val.strip().lower()
            mul = 1
            if val.endswith('gb'):
                mul = 1024**3
                val = val[:-2]
            elif val.endswith('mb'):
                mul = 1024**2
                val = val[:-2]
            elif val.endswith('kb'):
                mul = 1024
                val = val[:-2]
            return int(float(val) * mul)
        except Exception:
            return default_bytes

    def _tenant_caps(tenant: str) -> tuple[int, int]:
        # Per-tenant env override, else global tenant defaults
        tkey = (tenant or '').strip().upper().replace('-', '_')
        soft = _parse_cap_env(f'SHORTS_TENANT_{tkey}_SOFT', _parse_cap_env('SHORTS_TENANT_SOFT', 3 * 1024**3))
        hard = _parse_cap_env(f'SHORTS_TENANT_{tkey}_HARD', _parse_cap_env('SHORTS_TENANT_HARD', 4 * 1024**3))
        return soft, hard

    def _renditions_for(job: ShortJob, profile: str) -> list[dict]:
        if profile == 'shorts_premium' and job.content_class in {ShortJob.CLASS_PREFERRED, ShortJob.CLASS_PINNED}:
            return [
                {"name": "480p", "height": 480, "v_bitrate": "700k"},
                {"name": "720p", "height": 720, "v_bitrate": "1500k"},
                {"name": "1080p", "height": 1080, "v_bitrate": "3000k"},
            ]
        return [
            {"name": "480p", "height": 480, "v_bitrate": "700k"},
            {"name": "720p", "height": 720, "v_bitrate": "1500k"},
        ]

    def _estimate_bytes(duration_sec: float, job: ShortJob, profile: str) -> int:
        # Rough estimate: sum(video_bitrate + 128k audio) * duration
        if not duration_sec or duration_sec <= 0:
            return 0
        total_kbps = 0
        for r in _renditions_for(job, profile):
            try:
                v_kbps = int(r['v_bitrate'].rstrip('k'))
            except Exception:
                v_kbps = 1000
            total_kbps += (v_kbps + 128)
        total_bps = total_kbps * 1000
        bytes_no_headroom = int(total_bps * duration_sec / 8)
        # Add 10% headroom
        return int(bytes_no_headroom * 1.10)

    def _ytdlp_probe_attempt_args(client: str, allow_cookies: bool) -> list[str]:
        ua_android = 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36'
        ua_web = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
        ua = ua_android if client == 'android' else ua_web
        args: list[str] = [
            'yt-dlp',
            '--skip-download', '-J',
            '--extractor-args', f'youtube:player_client={client}',
            '--user-agent', ua,
            '--add-header', 'Referer:https://www.youtube.com',
        ]
        ck_browser = os.environ.get('YTDLP_COOKIES_FROM_BROWSER', '').strip()
        ck_file = os.environ.get('YTDLP_COOKIES_FILE', '').strip()
        if allow_cookies and (ck_browser or ck_file):
            if ck_browser:
                args += ['--cookies-from-browser', ck_browser]
            elif ck_file:
                args += ['--cookies', ck_file]
        extra = os.environ.get('YTDLP_EXTRA_ARGS', '').strip()
        if extra:
            try:
                import shlex as _sh
                args += _sh.split(extra)
            except Exception:
                pass
        return args

    def _probe_duration_with_ytdlp(url: str) -> float:
        # Mirror the download client/cookie logic for probing
        ck_browser = os.environ.get('YTDLP_COOKIES_FROM_BROWSER', '').strip()
        ck_file = os.environ.get('YTDLP_COOKIES_FILE', '').strip()
        cookies_present = bool(ck_browser or ck_file)
        attempts = (
            [{'client': 'web', 'allow_cookies': True}, {'client': 'android', 'allow_cookies': False}]
            if cookies_present else
            [{'client': 'android', 'allow_cookies': False}, {'client': 'web', 'allow_cookies': False}]
        )
        for att in attempts:
            try:
                cmd = _ytdlp_probe_attempt_args(att['client'], att['allow_cookies']) + [url]
                proc = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                if proc.returncode != 0:
                    continue
                data = json.loads(proc.stdout or '{}')
                dur = 0.0
                # yt-dlp may return duration as number or within entries
                if isinstance(data, dict):
                    dur = float(data.get('duration') or 0.0)
                    if not dur and isinstance(data.get('entries'), list) and data['entries']:
                        try:
                            dur = float(data['entries'][0].get('duration') or 0.0)
                        except Exception:
                            pass
                if dur and dur > 0:
                    return dur
            except Exception:
                continue
        return 0.0

    # Prepare paths
    media_root = Path(str(getattr(settings, 'MEDIA_ROOT', '/srv/media/short/videos')))
    # artifact_prefix e.g., shorts/{tenant}/{job_id}
    prefix = job.artifact_prefix or f"shorts/{job.tenant}/{job.id}"
    final_dir = media_root / prefix
    tmp_dir = Path(tempfile.mkdtemp(prefix=f"shortjob-{job.id}-"))

    try:
        # Preflight: probe duration, enforce cap, estimate and reserve bytes, check capacity
        profile = job.ladder_profile or 'shorts_v1'
        t_probe = time.monotonic()
        probed_duration = _probe_duration_with_ytdlp(job.source_url)
        if probed_duration and probed_duration > 0:
            ShortJob.objects.filter(id=job.id).update(duration_seconds=int(probed_duration))
            if probed_duration > 90.0:
                ShortJob.objects.filter(id=job.id).update(status=ShortJob.STATUS_FAILED, error_message="Video exceeds 90s cap (preflight)")
                logger.warning("shortjob.reject_duration", extra={"job_id": str(job.id), "duration": probed_duration})
                return False
        # Capacity check and reservation (atomic), include existing reservations
        reserve_bytes = _estimate_bytes(probed_duration, job, profile) if probed_duration else 0
        logger.info("shortjob.preflight", extra={
            "job_id": str(job.id),
            "duration": probed_duration,
            "profile": profile,
            "reserve_bytes": reserve_bytes,
            "probe_ms": int((time.monotonic() - t_probe) * 1000),
        })
        if reserve_bytes > 0:
            cap_soft = _parse_cap_env('SHORTS_CAP_SOFT', 9 * 1024**3)
            cap_hard = _parse_cap_env('SHORTS_CAP_HARD', 10 * 1024**3)
            from django.db.models import Sum
            with transaction.atomic():
                jlock = ShortJob.objects.select_for_update().get(id=job.id)
                # Include both used and existing reservations
                agg = ShortJob.objects.exclude(status=ShortJob.STATUS_DELETED).aggregate(u=Sum('used_bytes'), r=Sum('reserved_bytes'))
                current_total = int(agg.get('u') or 0) + int(agg.get('r') or 0)
                tagg = ShortJob.objects.filter(tenant=job.tenant).exclude(status=ShortJob.STATUS_DELETED).aggregate(u=Sum('used_bytes'), r=Sum('reserved_bytes'))
                tenant_total = int(tagg.get('u') or 0) + int(tagg.get('r') or 0)

                t_soft, t_hard = _tenant_caps(job.tenant)
                projected_global = current_total + reserve_bytes
                projected_tenant = tenant_total + reserve_bytes

                def _alert_checks(scope: str, used: int, projected: int, hard: int):
                    if hard <= 0:
                        return
                    pct = projected / hard * 100.0
                    if pct >= 95.0:
                        logger.error("shortjob.capacity.block", extra={"job_id": str(job.id), "scope": scope, "projected": projected, "hard": hard, "pct": round(pct,2)})
                        return "block"
                    if pct >= 80.0:
                        logger.warning("shortjob.capacity.warn", extra={"job_id": str(job.id), "scope": scope, "projected": projected, "hard": hard, "pct": round(pct,2)})
                    return None

                # Hard caps
                if projected_global > cap_hard:
                    ShortJob.objects.filter(id=job.id).update(status=ShortJob.STATUS_FAILED, error_message="Global hard cap exceeded")
                    logger.warning("shortjob.reject_global_hard", extra={"job_id": str(job.id), "current_total": current_total, "reserve_bytes": reserve_bytes, "cap_hard": cap_hard})
                    return False
                if projected_tenant > t_hard:
                    ShortJob.objects.filter(id=job.id).update(status=ShortJob.STATUS_FAILED, error_message="Tenant hard cap exceeded")
                    logger.warning("shortjob.reject_tenant_hard", extra={"job_id": str(job.id), "tenant": job.tenant, "tenant_total": tenant_total, "reserve_bytes": reserve_bytes, "tenant_cap_hard": t_hard})
                    return False

                if _alert_checks("global", current_total, projected_global, cap_hard) == "block" or _alert_checks("tenant", tenant_total, projected_tenant, t_hard) == "block":
                    ShortJob.objects.filter(id=job.id).update(status=ShortJob.STATUS_FAILED, error_message="Capacity critical: admissions blocked")
                    return False

                cls = job.content_class
                is_priority = cls in {ShortJob.CLASS_PREFERRED, ShortJob.CLASS_PINNED}
                if not is_priority and (projected_global > cap_soft or projected_tenant > t_soft):
                    ShortJob.objects.filter(id=job.id).update(status=ShortJob.STATUS_FAILED, error_message="Soft cap exceeded")
                    logger.warning("shortjob.reject_soft", extra={"job_id": str(job.id), "tenant": job.tenant, "class": cls, "projected_global": projected_global, "cap_soft": cap_soft, "projected_tenant": projected_tenant, "tenant_soft": t_soft})
                    return False
                if is_priority and (projected_global > cap_soft or projected_tenant > t_soft):
                    logger.info("shortjob.soft_overridden", extra={"job_id": str(job.id), "tenant": job.tenant, "class": cls, "projected_global": projected_global, "cap_soft": cap_soft, "projected_tenant": projected_tenant, "tenant_soft": t_soft})

                # Reserve atomically
                jlock.reserved_bytes = reserve_bytes
                jlock.save(update_fields=["reserved_bytes", "updated_at"])

        # Move to downloading
        with transaction.atomic():
            j = ShortJob.objects.select_for_update(skip_locked=True).get(id=job.id)
            if j.status not in {ShortJob.STATUS_QUEUED, ShortJob.STATUS_FAILED}:
                return True
            j.status = ShortJob.STATUS_DOWNLOADING
            j.error_message = ''
            j.save(update_fields=["status", "error_message", "updated_at"])

        # Download source with yt-dlp (with retries, android UA, optional cookies)
        src_path = tmp_dir / "source.mp4"
        t_dl_start = time.monotonic()

        # Cookie/env detection (used per-attempt)
        ck_browser = os.environ.get('YTDLP_COOKIES_FROM_BROWSER', '').strip()
        ck_file = os.environ.get('YTDLP_COOKIES_FILE', '').strip()
        cookies_present = bool(ck_browser or ck_file)

        def _ytdlp_args(client: str, allow_cookies: bool) -> list[str]:
            # User agents per client
            ua_android = 'Mozilla/5.0 (Linux; Android 10) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Mobile Safari/537.36'
            ua_web = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15'
            ua = ua_android if client == 'android' else ua_web

            args: list[str] = [
                'yt-dlp',
                '--extractor-args', f'youtube:player_client={client}',
                '--user-agent', ua,
                '--add-header', 'Referer:https://www.youtube.com',
            ]
            # Attach cookies only if attempt allows and provided
            if allow_cookies and cookies_present:
                if ck_browser:
                    args += ['--cookies-from-browser', ck_browser]
                elif ck_file:
                    args += ['--cookies', ck_file]
            # Optional extra args passthrough
            extra = os.environ.get('YTDLP_EXTRA_ARGS', '').strip()
            if extra:
                try:
                    import shlex as _sh
                    args += _sh.split(extra)
                except Exception:
                    pass
            return args

        format_chain = [
            'bv*+ba/bestvideo[height<=720]+bestaudio/18/best[ext=mp4][height<=720]/best',
            '18',
        ]

        # Attempt order: with/without cookies and client types
        attempts = []
        if cookies_present:
            # Cookies do not work with android client; prefer web+cookies, then android w/o cookies
            attempts = [
                {'client': 'web', 'allow_cookies': True},
                {'client': 'android', 'allow_cookies': False},
            ]
        else:
            attempts = [
                {'client': 'android', 'allow_cookies': False},
                {'client': 'web', 'allow_cookies': False},
            ]

        last_err: Exception | None = None
        for att in attempts:
            for fmt in format_chain:
                try:
                    cmd = _ytdlp_args(att['client'], att['allow_cookies']) + [
                        '-f', fmt,
                        '-o', str(src_path),
                        '--merge-output-format', 'mp4',
                        job.source_url,
                    ]
                    logger.info("shortjob.download.try", extra={"job_id": str(job.id), "client": att['client'], "cookies": att['allow_cookies'], "format": fmt})
                    _run(cmd)
                    last_err = None
                    logger.info("shortjob.download.success", extra={
                        "job_id": str(job.id),
                        "elapsed_ms": int((time.monotonic() - t_dl_start) * 1000),
                        "client": att['client'],
                        "format": fmt,
                    })
                    break
                except Exception as e:
                    last_err = e
                    logger.warning("shortjob.download.fail", extra={
                        "job_id": str(job.id), "client": att['client'], "cookies": att['allow_cookies'], "format": fmt,
                    })
                    continue
            if last_err is None:
                break
        if last_err is not None:
            msg = str(last_err).lower()
            logger.error("shortjob.download.error", extra={"job_id": str(job.id), "error": msg[:200]})
            # Permanent indicators
            if any(s in msg for s in [
                'http error 401', 'http error 403', 'http error 404', 'http error 410',
                'private video', 'copyright', 'this video is unavailable', 'this video is not available',
                'sign in to confirm your age',
            ]):
                raise PermanentError(str(last_err))
            # Transient indicators
            if any(s in msg for s in [
                'timed out', 'timeout', 'temporary failure', 'connection reset', 'connection refused',
                'ssl', 'tls', 'remote end closed connection', 'http error 5']):
                raise TransientError(str(last_err))
            # Default to transient to allow retry once
            raise TransientError(str(last_err))

        # Probe duration and enforce cap 90s
        duration = _ffprobe_duration(src_path)
        ShortJob.objects.filter(id=job.id).update(duration_seconds=int(duration))
        if duration and duration > 90.0:
            # Default policy: reject if >90s
            ShortJob.objects.filter(id=job.id).update(status=ShortJob.STATUS_FAILED, error_message="Video exceeds 90s cap")
            logger.warning("shortjob.reject_duration_post", extra={"job_id": str(job.id), "duration": duration})
            return False

        # Transcode to HLS renditions
        with transaction.atomic():
            ShortJob.objects.filter(id=job.id, status=ShortJob.STATUS_DOWNLOADING).update(status=ShortJob.STATUS_TRANSCODING)

        # Prepare output dir
        final_dir.mkdir(parents=True, exist_ok=True)
        work_dir = tmp_dir / "hls"
        work_dir.mkdir(parents=True, exist_ok=True)

        # Define ladder profiles (enforce 1080p only for Preferred/Pinned)
        profile = job.ladder_profile or 'shorts_v1'
        if profile == 'shorts_premium' and job.content_class not in {ShortJob.CLASS_PREFERRED, ShortJob.CLASS_PINNED}:
            logger.info("shortjob.profile.downgrade", extra={"job_id": str(job.id), "from": profile, "to": "shorts_v1", "class": job.content_class})
            profile = 'shorts_v1'
        renditions: list[dict] = []
        if profile == 'shorts_premium' and job.content_class in {ShortJob.CLASS_PREFERRED, ShortJob.CLASS_PINNED}:
            renditions = [
                {"name": "480p", "height": 480, "v_bitrate": "700k"},
                {"name": "720p", "height": 720, "v_bitrate": "1500k"},
                {"name": "1080p", "height": 1080, "v_bitrate": "3000k"},
            ]
        else:
            renditions = [
                {"name": "480p", "height": 480, "v_bitrate": "700k"},
                {"name": "720p", "height": 720, "v_bitrate": "1500k"},
            ]

        audio_bitrate = "128k"
        segment_time = "4"

        t_tx_start = time.monotonic()
        variant_entries = []
        for r in renditions:
            out_dir = work_dir / r["name"]
            out_dir.mkdir(parents=True, exist_ok=True)
            playlist = out_dir / "index.m3u8"
            seg_pattern = out_dir / "segment_%03d.ts"
            scale_filter = f"scale=-2:{r['height']}"
            ffmpeg_cmd = [
                'ffmpeg', '-y', '-i', str(src_path),
                '-vf', scale_filter, '-c:v', 'h264', '-profile:v', 'main', '-preset', 'veryfast', '-b:v', r['v_bitrate'], '-maxrate', r['v_bitrate'], '-bufsize', '2M',
                '-c:a', 'aac', '-b:a', audio_bitrate,
                '-hls_time', segment_time, '-hls_playlist_type', 'vod', '-hls_segment_filename', str(seg_pattern), str(playlist)
            ]
            t_one = time.monotonic()
            try:
                _run(ffmpeg_cmd)
            except Exception as e:
                msg = str(e).lower()
                # Basic classification for ffmpeg
                if any(s in msg for s in ["invalid data", "unsupported", "no such file"]):
                    raise PermanentError(str(e))
                raise TransientError(str(e))
            logger.info("shortjob.transcode.rendition", extra={
                "job_id": str(job.id), "rendition": r['name'], "height": r['height'],
                "elapsed_ms": int((time.monotonic() - t_one) * 1000),
            })
            # Estimate bandwidth for master (rough): convert kbps to bps, add audio
            try:
                v_kbps = int(r['v_bitrate'].rstrip('k'))
            except Exception:
                v_kbps = 1000
            bandwidth = (v_kbps + 128) * 1000
            variant_entries.append({"name": r['name'], "bandwidth": bandwidth, "path": f"{r['name']}/index.m3u8"})

        # Write master playlist
        master_path = work_dir / 'master.m3u8'
        lines = ["#EXTM3U", "#EXT-X-VERSION:3"]
        for v in variant_entries:
            lines.append(f"#EXT-X-STREAM-INF:BANDWIDTH={v['bandwidth']}")
            lines.append(v['path'])
        master_path.write_text("\n".join(lines), encoding='utf-8')
        logger.info("shortjob.transcode.done", extra={
            "job_id": str(job.id), "renditions": [v['name'] for v in variant_entries],
            "elapsed_ms": int((time.monotonic() - t_tx_start) * 1000),
        })

        # Move HLS to final dir atomically
        # Remove existing dir if present then move
        if final_dir.exists():
            shutil.rmtree(final_dir)
        shutil.move(str(work_dir), str(final_dir))

        # Compute used bytes
        used = 0
        for p in final_dir.rglob('*'):
            if p.is_file():
                try:
                    used += p.stat().st_size
                except Exception:
                    continue

        # Build public URL under /media/ alias
        # MEDIA_ROOT parent is /srv/media/short/, alias maps to /media/
        # So file at /srv/media/short/videos/shorts/... -> /media/videos/shorts/...
        public_master_url = f"/media/{final_dir.relative_to(Path(settings.MEDIA_ROOT).parent)}" if Path(settings.MEDIA_ROOT).parent in final_dir.parents else f"/media/videos/{prefix}/master.m3u8"
        # Ensure it points to master.m3u8
        if not public_master_url.endswith('master.m3u8'):
            public_master_url = public_master_url.rstrip('/') + '/master.m3u8'

        with transaction.atomic():
            j = ShortJob.objects.select_for_update().get(id=job.id)
            j.used_bytes = used
            j.reserved_bytes = used  # simple conversion; reservation logic can refine later
            j.hls_master_url = public_master_url
            j.status = ShortJob.STATUS_READY
            j.save(update_fields=["used_bytes", "reserved_bytes", "hls_master_url", "status", "updated_at"])

        total_ms = int((time.monotonic() - t_job_start) * 1000)
        logger.info("shortjob.done", extra={
            "job_id": str(job.id), "used_bytes": used, "hls": public_master_url, "elapsed_ms": total_ms,
        })

        # Update simple metrics snapshot
        try:
            from django.db.models import Sum, Count
            agg = ShortJob.objects.aggregate(
                used=Sum('used_bytes'),
            )
            counts = ShortJob.objects.values('status').annotate(c=Count('id'))
            by_status = {row['status']: row['c'] for row in counts}
            used_total = int(agg.get('used') or 0)
            cap_soft = _parse_cap_env('SHORTS_CAP_SOFT', 9 * 1024**3)
            cap_hard = _parse_cap_env('SHORTS_CAP_HARD', 10 * 1024**3)
            pct_soft = float(used_total) / cap_soft * 100.0 if cap_soft else 0.0
            pct_hard = float(used_total) / cap_hard * 100.0 if cap_hard else 0.0
            metrics = {
                "ts": timezone.now().isoformat(),
                "counts": by_status,
                "used_bytes": used_total,
                "cap_soft": cap_soft,
                "cap_hard": cap_hard,
                "pct_soft": round(pct_soft, 2),
                "pct_hard": round(pct_hard, 2),
            }
            mdir = media_root / 'shorts'
            mdir.mkdir(parents=True, exist_ok=True)
            (mdir / 'metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
        except Exception:
            pass

        return True
    except Exception as exc:
        ShortJob.objects.filter(id=job.id).update(status=ShortJob.STATUS_FAILED, error_message=str(exc)[:1000], reserved_bytes=0)
        logger.exception("shortjob.error", extra={"job_id": str(job.id)})
        # Best-effort metrics update on failure
        try:
            from django.db.models import Sum, Count
            agg = ShortJob.objects.aggregate(used=Sum('used_bytes'))
            counts = ShortJob.objects.values('status').annotate(c=Count('id'))
            by_status = {row['status']: row['c'] for row in counts}
            used_total = int(agg.get('used') or 0)
            cap_soft = _parse_cap_env('SHORTS_CAP_SOFT', 9 * 1024**3)
            cap_hard = _parse_cap_env('SHORTS_CAP_HARD', 10 * 1024**3)
            pct_soft = float(used_total) / cap_soft * 100.0 if cap_soft else 0.0
            pct_hard = float(used_total) / cap_hard * 100.0 if cap_hard else 0.0
            metrics = {
                "ts": timezone.now().isoformat(),
                "counts": by_status,
                "used_bytes": used_total,
                "cap_soft": cap_soft,
                "cap_hard": cap_hard,
                "pct_soft": round(pct_soft, 2),
                "pct_hard": round(pct_hard, 2),
            }
            mdir = media_root / 'shorts'
            mdir.mkdir(parents=True, exist_ok=True)
            (mdir / 'metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
        except Exception:
            pass
        raise
    finally:
        try:
            if tmp_dir.exists():
                shutil.rmtree(tmp_dir)
        except Exception:
            pass


@shared_task(bind=True)
def evict_shorts_low_water(self) -> dict:
    from django.db.models import Sum
    media_root = Path(str(getattr(settings, 'MEDIA_ROOT', '/srv/media/short/videos')))
    # Determine thresholds
    cap_soft = _parse_cap_env('SHORTS_CAP_SOFT', 9 * 1024**3)
    low_water_env = os.environ.get('SHORTS_LOW_WATER')
    low_water = _parse_cap_env('SHORTS_LOW_WATER', int(cap_soft * 0.85)) if low_water_env or cap_soft else int(9 * 1024**3 * 0.85)

    # Compute current used
    used_total = int(ShortJob.objects.aggregate(used=Sum('used_bytes')).get('used') or 0)
    if used_total <= low_water:
        logger.info("shorts.evict.skip", extra={"used_bytes": used_total, "low_water": low_water})
        return {"evicted": 0, "used_bytes": used_total}

    # Class order: Ephemeral -> Normal -> Preferred (skip Pinned)
    class_order = [getattr(ShortJob, 'CLASS_EPHEMERAL', 'ephemeral'), getattr(ShortJob, 'CLASS_NORMAL', 'normal'), getattr(ShortJob, 'CLASS_PREFERRED', 'preferred')]
    evicted = 0

    def _delete_job(j: ShortJob) -> int:
        nonlocal media_root
        bytes_freed = int(j.used_bytes or 0)
        try:
            # Delete folder
            if j.artifact_prefix:
                p = media_root / j.artifact_prefix
                if p.exists():
                    shutil.rmtree(p, ignore_errors=True)
            # Update DB
            ShortJob.objects.filter(id=j.id).update(status=ShortJob.STATUS_DELETED, used_bytes=0, reserved_bytes=0, updated_at=timezone.now())
            logger.info("shorts.evict.delete", extra={"job_id": str(j.id), "freed": bytes_freed, "class": j.content_class})
        except Exception as e:
            logger.warning("shorts.evict.delete_fail", extra={"job_id": str(j.id), "error": str(e)[:200]})
            bytes_freed = 0
        return bytes_freed

    for cls in class_order:
        if used_total <= low_water:
            break
        qs = ShortJob.objects.filter(content_class=cls, status=ShortJob.STATUS_READY).order_by('updated_at')
        for j in qs[:500]:  # safety cap per run
            freed = _delete_job(j)
            evicted += 1 if freed > 0 else 0
            used_total = max(0, used_total - freed)
            if used_total <= low_water:
                break

    # Refresh metrics after eviction
    try:
        from django.db.models import Count
        agg = ShortJob.objects.aggregate(used=Sum('used_bytes'))
        counts = ShortJob.objects.values('status').annotate(c=Count('id'))
        by_status = {row['status']: row['c'] for row in counts}
        used_total = int(agg.get('used') or 0)
        cap_hard = _parse_cap_env('SHORTS_CAP_HARD', 10 * 1024**3)
        pct_soft = float(used_total) / cap_soft * 100.0 if cap_soft else 0.0
        pct_hard = float(used_total) / cap_hard * 100.0 if cap_hard else 0.0
        metrics = {
            "ts": timezone.now().isoformat(),
            "counts": by_status,
            "used_bytes": used_total,
            "cap_soft": cap_soft,
            "cap_hard": cap_hard,
            "pct_soft": round(pct_soft, 2),
            "pct_hard": round(pct_hard, 2),
        }
        mdir = media_root / 'shorts'
        mdir.mkdir(parents=True, exist_ok=True)
        (mdir / 'metrics.json').write_text(json.dumps(metrics, indent=2), encoding='utf-8')
    except Exception:
        pass

    logger.info("shorts.evict.done", extra={"evicted": evicted, "used_bytes": used_total, "low_water": low_water})
    return {"evicted": evicted, "used_bytes": used_total, "low_water": low_water}


# Helper to select recent shorts and enqueue ingestion jobs

def select_and_enqueue_recent_shorts(tenant: str, limit: int = 10, per_playlist_limit: int | None = None) -> list[dict]:
    try:
        limit = max(1, min(int(limit), 50))
    except Exception:
        limit = 10
    results: list[dict] = []

    if per_playlist_limit and per_playlist_limit > 0:
        # Fair distribution: collect recent videos per playlist, then round-robin up to overall limit
        pls = (
            Playlist.objects.filter(is_shorts=True, is_active=True, channel__tenant=tenant)
            .order_by("-latest_video_published_at", "-last_synced_at")
        )
        per_lists: list[list[Video]] = []
        for pl in pls:
            pv = list(
                Video.objects.select_related("playlist", "channel")
                .filter(playlist=pl)
                .order_by("-published_at", "-position")[: per_playlist_limit]
            )
            if pv:
                per_lists.append(pv)

        picked: list[Video] = []
        idx = 0
        # Round-robin pick
        while len(picked) < limit and per_lists:
            removed = []
            for li, lst in enumerate(per_lists):
                if idx < len(lst):
                    picked.append(lst[idx])
                    if len(picked) >= limit:
                        break
                else:
                    removed.append(li)
            # Trim exhausted lists
            if removed:
                per_lists = [lst for i, lst in enumerate(per_lists) if i not in removed]
            idx += 1
        vids = picked
    else:
        vids = (
            Video.objects.select_related("playlist", "channel")
            .filter(playlist__is_shorts=True, playlist__is_active=True, channel__tenant=tenant)
            .order_by("-published_at", "-position")[: limit]
        )

    for v in vids:
        vid = getattr(v, "video_id", None)
        if not vid:
            continue
        source_url = f"https://youtu.be/{vid}"
        base_qs = ShortJob.objects.filter(tenant=tenant).exclude(status=ShortJob.STATUS_DELETED)
        existing_ready = base_qs.filter(status=ShortJob.STATUS_READY, source_url__icontains=vid).order_by("-updated_at").first()
        if existing_ready:
            results.append({"video_id": vid, "job_id": str(existing_ready.id), "status": existing_ready.status, "deduped": True})
            continue
        existing_inprog = base_qs.filter(
            status__in=[ShortJob.STATUS_QUEUED, ShortJob.STATUS_DOWNLOADING, ShortJob.STATUS_TRANSCODING],
            source_url__icontains=vid,
        ).order_by("-updated_at").first()
        if existing_inprog:
            results.append({"video_id": vid, "job_id": str(existing_inprog.id), "status": existing_inprog.status, "deduped": True})
            continue
        job = ShortJob.objects.create(
            tenant=tenant,
            requested_by=None,
            source_url=source_url,
            status=ShortJob.STATUS_QUEUED,
            ladder_profile="shorts_v1",
            content_class=getattr(ShortJob, "CLASS_EPHEMERAL", "ephemeral"),
        )
        job.artifact_prefix = f"shorts/{tenant}/{job.id}"
        job.save(update_fields=["artifact_prefix", "updated_at"])
        try:
            process_short_job.delay(str(job.id))
        except Exception:
            pass
        results.append({"video_id": vid, "job_id": str(job.id), "status": job.status, "deduped": False})
    return results


@shared_task(bind=True)
def batch_import_recent_shorts(self, tenant: str = "ontime", limit: int = 10, per_playlist_limit: int | None = None) -> dict:
    results = select_and_enqueue_recent_shorts(tenant=tenant, limit=limit, per_playlist_limit=per_playlist_limit)
    return {"tenant": tenant, "count": len(results), "results": results}
