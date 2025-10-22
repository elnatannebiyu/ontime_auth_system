from rest_framework import viewsets, permissions, filters, status
from rest_framework.response import Response
from rest_framework.views import APIView
from django.shortcuts import get_object_or_404
from django.conf import settings
from django.http import HttpResponse
import json
from urllib.parse import urlparse

from .models import Live
from .serializers import LiveSerializer

# Swagger imports guarded similar to onchannels
_ENABLE_SWAGGER = getattr(settings, 'ENABLE_SWAGGER', False) or settings.DEBUG
try:
    if _ENABLE_SWAGGER:
        from drf_yasg import openapi  # type: ignore
        from drf_yasg.utils import swagger_auto_schema  # type: ignore
    else:
        raise ImportError
except Exception:
    def swagger_auto_schema(*args, **kwargs):  # type: ignore
        def _decorator(func):
            return func
        return _decorator
    class _OpenApiShim:  # type: ignore
        IN_HEADER = 'header'
        TYPE_STRING = 'string'
        class Parameter:  # type: ignore
            def __init__(self, name, in_, description='', type=None, required=False, default=None):
                self.name = name
                self.in_ = in_
                self.description = description
                self.type = type
                self.required = required
                self.default = default
    openapi = _OpenApiShim()  # type: ignore


class LiveViewSet(viewsets.ReadOnlyModelViewSet):
    queryset = Live.objects.select_related('channel').all()
    serializer_class = LiveSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = [
        'channel__id_slug', 'channel__name_en', 'channel__name_am', 'title'
    ]
    ordering_fields = ['updated_at']

    PARAM_TENANT = openapi.Parameter(
        name='X-Tenant-Id',
        in_=openapi.IN_HEADER,
        description='Tenant slug (e.g., ontime)',
        type=openapi.TYPE_STRING,
        required=True,
    )

    @swagger_auto_schema(manual_parameters=[PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        user = self.request.user
        # Non-admins: active only
        if not (user.is_staff or user.has_perm('live.change_live')):
            qs = qs.filter(is_active=True)
        tenant = self.request.headers.get('X-Tenant-Id') or self.request.query_params.get('tenant') or 'ontime'
        qs = qs.filter(tenant=tenant)
        # Optional filter by channel slug
        ch = self.request.query_params.get('channel')
        if ch:
            qs = qs.filter(channel__id_slug=ch)
        return qs


class LiveBySlugView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @swagger_auto_schema(manual_parameters=[LiveViewSet.PARAM_TENANT])
    def get(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.query_params.get('tenant') or 'ontime'
        qs = Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug)
        if not (request.user.is_staff or request.user.has_perm('live.change_live')):
            qs = qs.filter(is_active=True)
        obj = get_object_or_404(qs)
        return Response(LiveSerializer(obj, context={'request': request}).data)


class LivePreviewView(APIView):
    """Serve a minimal HTML page that plays the live HLS/DASH using hls.js (for HLS) or native.

    This is intended for quick manual preview in a browser. It does not require authentication,
    but only serves streams where is_previewable=True. It does NOT proxy the media; the browser
    will request the manifest/segments directly from the CDN defined in playback_url.
    """
    permission_classes = [permissions.AllowAny]
    throttle_classes: list = []  # disable throttling for preview

    def get(self, request, slug: str):
        # Resolve tenant (header or query param for preview convenience)
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        # Only allow previewable streams; require is_active OR previewable explicitly
        qs = Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug, is_previewable=True)
        obj = get_object_or_404(qs)
        url = obj.playback_url
        title = obj.title or getattr(obj.channel, 'name_en', None) or getattr(obj.channel, 'name_am', None) or slug
        # Basic HTML5 + hls.js loader (token replacement to avoid Python f-string/% conflicts)
        html = """
<!DOCTYPE html>
<html lang=\"en\">
<head>
  <meta charset=\"utf-8\" />
  <meta name=\"viewport\" content=\"width=device-width, initial-scale=1\" />
  <title>Preview: __TITLE__</title>
  <style>
    body { margin:0; background:#111; color:#eee; font-family:system-ui,-apple-system,Segoe UI,Roboto,Ubuntu; }
    header { padding:12px 16px; background:#181818; position:sticky; top:0; }
    .wrap { padding:16px; }
    video { width:100%; max-height:80vh; background:#000; }
    .meta { margin-top:8px; font-size:14px; color:#bbb; word-break:break-all; }
    .logs { margin-top:12px; padding:8px; background:#0f0f0f; border:1px solid #333; border-radius:6px; max-height:30vh; overflow:auto; font-family:monospace; font-size:12px; color:#d4d4d4; }
    .controls { margin-top:8px; }
    .btn { background:#2d6cdf; color:#fff; border:0; padding:6px 10px; border-radius:6px; cursor:pointer; }
  </style>
  <script src=\"https://cdn.jsdelivr.net/npm/hls.js@1.5.10/dist/hls.min.js\"></script>
  <script>
    function addLog(msg) {
      try {
        const el = document.getElementById('logs');
        const p = document.createElement('div');
        const ts = new Date().toLocaleTimeString();
        p.textContent = '[' + ts + '] ' + msg;
        el.appendChild(p);
        el.scrollTop = el.scrollHeight;
      } catch (e) {}
    }
    document.addEventListener('DOMContentLoaded', () => {
      const video = document.getElementById('player');
      // Use proxy so we can inject required headers server-side
      const src = '/api/live/proxy/'+encodeURIComponent('__SLUG__')+'/manifest/?tenant='+encodeURIComponent('__TENANT__');
      addLog('Initializing preview...');
      addLog('Source URL: ' + src);
      // Force hls.js so we can attach X-Tenant-Id header; native HLS cannot set custom headers.
      const forceHls = true;
      if (!forceHls && video.canPlayType('application/vnd.apple.mpegurl')) {
        addLog('Using native HLS');
        video.src = src;
        video.play().then(()=>addLog('Video play() resolved (native)')).catch(e=>addLog('Video play() rejected (native): ' + e));
      } else if (window.Hls && Hls.isSupported()) {
        addLog('Using hls.js');
        const hls = new Hls({
          maxBufferLength: 30,
          liveSyncDuration: 3,
          enableWorker: true,
          debug: true,
          xhrSetup: (xhr, url) => {
            try { xhr.setRequestHeader('X-Tenant-Id', '__TENANT__'); } catch(e) {}
          }
        });
        hls.on(Hls.Events.MEDIA_ATTACHED, () => addLog('HLS MEDIA_ATTACHED'));
        hls.on(Hls.Events.MANIFEST_LOADING, () => addLog('HLS MANIFEST_LOADING'));
        hls.on(Hls.Events.MANIFEST_PARSED, (e, data) => addLog('HLS MANIFEST_PARSED: levels=' + (data && data.levels ? data.levels.length : 'n/a')));
        hls.on(Hls.Events.LEVEL_LOADING, (e, data) => addLog('HLS LEVEL_LOADING: level=' + (data && data.level ? data.level : 'n/a')));
        hls.on(Hls.Events.LEVEL_LOADED, (e, data) => addLog('HLS LEVEL_LOADED: details=' + (data && data.details && data.details.totalduration ? data.details.totalduration.toFixed(2)+'s' : 'n/a')));
        hls.on(Hls.Events.FRAG_LOADING, (e, data) => addLog('HLS FRAG_LOADING: ' + (data && data.frag && data.frag.sn !== undefined ? 'sn=' + data.frag.sn : '')));
        hls.on(Hls.Events.ERROR, (e, data) => addLog('HLS ERROR: type=' + (data && data.type) + ' details=' + (data && data.details) + ' fatal=' + (data && data.fatal)));
        hls.loadSource(src);
        hls.attachMedia(video);
        hls.on(Hls.Events.MANIFEST_PARSED, function() { video.play().then(()=>addLog('Video play() resolved (hls.js)')).catch(e=>addLog('Video play() rejected (hls.js): ' + e)); });
      } else {
        document.getElementById('err').textContent = 'Your browser does not support HLS playback.';
        addLog('No native HLS and hls.js not supported');
      }
      // Basic video element event logging
      const evs = ['loadedmetadata','loadeddata','canplay','canplaythrough','playing','pause','waiting','stalled','error','ended'];
      evs.forEach(ev => video.addEventListener(ev, () => addLog('VIDEO ' + ev)));

      // Unmute/volume controls for production
      const unmuteBtn = document.getElementById('unmuteBtn');
      const vol = localStorage.getItem('preview_volume');
      try { if (vol != null) { video.volume = Math.max(0, Math.min(1, parseFloat(vol))); } } catch(e) {}
      unmuteBtn.addEventListener('click', () => {
        try { video.muted = false; video.play(); addLog('Unmuted'); } catch(e) { addLog('Unmute failed: ' + e); }
      });
      video.addEventListener('volumechange', () => {
        try { localStorage.setItem('preview_volume', String(video.volume)); } catch(e) {}
      });
    });
  </script>
</head>
<body>
  <header>
    <strong>Preview:</strong> __TITLE__
  </header>
  <div class=\"wrap\">
    <video id=\"player\" controls playsinline muted></video>
    <div class=\"controls\"><button id=\"unmuteBtn\" class=\"btn\">Unmute</button></div>
    <div id=\"err\" style=\"color:#ff6666; margin-top:8px;\"></div>
    <div class=\"meta\">Source: __URL__ (proxied)</div>
    <div class=\"logs\" id=\"logs\"></div>
  </div>
</body>
</html>
"""
        html = html.replace('__TITLE__', title).replace('__URL__', url).replace('__SLUG__', slug).replace('__TENANT__', tenant)
        return HttpResponse(html)


class LiveProxyBase:
    """Shared helpers for proxying HLS with required headers."""
    UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10.15; rv:143.0) Gecko/20100101 Firefox/143.0'

    @staticmethod
    def _headers():
        return {
            'User-Agent': LiveProxyBase.UA,
            'Origin': 'https://embed.novastream.et',
            'Referer': 'https://embed.novastream.et/',
            'Accept': 'application/vnd.apple.mpegurl,application/x-mpegURL,*/*',
            'Accept-Language': 'en-US,en;q=0.5',
            'Accept-Encoding': 'identity',
        }

    @staticmethod
    def _http_get(url: str, stream: bool = False, extra_headers: dict | None = None):
        import requests
        headers = LiveProxyBase._headers()
        if extra_headers:
            try:
                headers.update({k: v for k, v in extra_headers.items() if v is not None})
            except Exception:
                pass
        resp = requests.get(url, headers=headers, timeout=15, stream=stream)
        return resp

    @staticmethod
    def _join_url(base_url: str, part: str) -> str:
        from urllib.parse import urljoin
        return urljoin(base_url, part)


class LiveProxyManifestView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes: list = []  # disable throttling for proxy manifest

    def get(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        obj = get_object_or_404(
            Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug, is_previewable=True)
        )
        # Allow overriding the upstream playlist via query (?url=...), for nested variant playlists
        upstream = request.GET.get('url')

        # Per-channel signer support (optional). Configure in Live.meta, e.g.:
        # {
        #   "signer": {
        #     "url": "https://example.com/api/sign?ch={slug}",
        #     "method": "GET",
        #     "headers": {"Origin":"...","Referer":"...","User-Agent":"..."},
        #     "body": null,
        #     "response_path": "m3u8",  # or "url"
        #     "ttl_ms": 1500000          # optional
        #   ,
        #   "bootstrap": { "start_url": "https://www.fanamc.com/english/live" }  # optional: fetch page to seed cookies
        #   },
        #   "allowed_upstream": ["edge.example.com"]
        # }
        meta = getattr(obj, 'meta', None) or {}
        signer = meta.get('signer') or {}
        bootstrap = meta.get('bootstrap') or {}
        allowed_upstream = set(meta.get('allowed_upstream') or [])
        if not allowed_upstream:
            allowed_upstream = {'edge.novastream.et'}

        DEFAULT_SIGN_TTL_MS = 25 * 60 * 1000
        # simple in-process cache: key by (tenant, slug)
        global _SIGN_CACHE
        try:
            _SIGN_CACHE
        except NameError:
            _SIGN_CACHE = {}

        def _cache_key() -> str:
            return f"{tenant}:{slug}"

        def _cache_get():
            entry = _SIGN_CACHE.get(_cache_key())
            if entry and entry.get('expires_at', 0) > __import__('time').time() * 1000:
                return entry.get('m3u8')
            return None

        def _cache_set(m3u8_url: str, ttl_ms: int):
            _SIGN_CACHE[_cache_key()] = {
                'm3u8': m3u8_url,
                'expires_at': (__import__('time').time() * 1000) + max(60_000, ttl_ms or DEFAULT_SIGN_TTL_MS),
            }

        def _extract_from_payload(payload):
            if isinstance(payload, str):
                # Try direct text first; if HTML, try to find a .m3u8 URL within
                txt = payload.strip()
                if txt.lower().startswith('<!doctype') or txt.lower().startswith('<html'):
                    import re
                    m = re.search(r'https?://[^\s"\']+\.m3u8[^\s"\']*', txt)
                    return m.group(0) if m else None
                return txt
            if isinstance(payload, dict):
                # simple path lookup
                path = (signer.get('response_path') or 'm3u8').split('.')
                cur = payload
                for p in path:
                    if isinstance(cur, dict) and p in cur:
                        cur = cur[p]
                    else:
                        # fallbacks
                        return payload.get('m3u8') or payload.get('url') or payload.get('playlist')
                if isinstance(cur, str):
                    return cur
            return None

        def _fetch_signed_url(force: bool = False):
            cached = _cache_get()
            if cached and not force:
                return cached
            if not signer or not signer.get('url'):
                return None
            import requests
            url_t = str(signer.get('url')).replace('{slug}', slug)
            method = (signer.get('method') or 'GET').upper()
            headers = signer.get('headers') or {}
            body = signer.get('body')
            if isinstance(body, str):
                body = body.replace('{slug}', slug)
            ttl_ms = int(signer.get('ttl_ms') or DEFAULT_SIGN_TTL_MS)
            try:
                # If no Cookie provided, optionally bootstrap cookies by visiting a start page (e.g., fanamc live page)
                session = None
                cookie_hdr = (headers.get('Cookie') or headers.get('cookie'))
                if not cookie_hdr and bootstrap.get('start_url'):
                    session = requests.Session()
                    # Visit start page to seed cookies
                    session.get(bootstrap['start_url'], headers={
                        'User-Agent': headers.get('User-Agent') or LiveProxyBase.UA,
                        'Accept': headers.get('Accept') or 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
                        'Referer': headers.get('Referer') or headers.get('Origin') or '',
                        'Origin': headers.get('Origin') or '',
                    }, timeout=15)
                    # Use session to call signer without explicit Cookie header
                    resp = session.request(method, url_t, headers={k: v for k, v in headers.items() if k.lower() != 'cookie'}, data=body, timeout=15)
                else:
                    resp = requests.request(method, url_t, headers=headers, data=body, timeout=15)
                resp.raise_for_status()
                payload = resp.json() if 'application/json' in (resp.headers.get('Content-Type') or '') else resp.text
                signed_url = _extract_from_payload(payload)
                if not signed_url:
                    return None
                _cache_set(signed_url, ttl_ms)
                return signed_url
            except Exception:
                return None

        # Decide upstream
        if not upstream:
            # Force re-sign path: meta.signer.always=true OR query resign=1
            force_every_time = False
            try:
                force_every_time = bool(signer.get('always'))
            except Exception:
                force_every_time = False
            if request.GET.get('resign') == '1':
                force_every_time = True

            if force_every_time and signer:
                upstream = _fetch_signed_url(force=True) or obj.playback_url
            else:
                upstream = _cache_get() or _fetch_signed_url(force=False) or obj.playback_url

        # Fetch upstream manifest with required headers
        def _fetch_manifest(url_: str):
            resp = LiveProxyBase._http_get(url_, stream=False)
            ok = 200 <= resp.status_code < 300
            return ok, resp

        ok, resp = _fetch_manifest(upstream)
        if (not ok) and signer and resp is not None and resp.status_code in (401, 403):
            # force refresh signed URL once and retry
            new_upstream = _fetch_signed_url(force=True)
            if new_upstream:
                upstream = new_upstream
                ok, resp = _fetch_manifest(upstream)
        if not ok:
            status_code = getattr(resp, 'status_code', 502) if resp is not None else 502
            body = getattr(resp, 'text', '') if resp is not None else ''
            return HttpResponse(f"# Proxy error ({status_code}): {body[:300]}", status=502, content_type='text/plain')

        text = resp.text or ''

        # Rewrite relative segment/playlist URIs to our segment proxy
        base = upstream.rsplit('/', 1)[0] + '/'
        out_lines = []
        for line in text.splitlines():
            if not line or line.startswith('#'):
                out_lines.append(line)
                continue
            # Compute absolute URL for allowlist check
            from urllib.parse import urljoin
            abs_url = line if line.startswith(('http://', 'https://')) else urljoin(base, line)
            # Enforce upstream allowlist
            from urllib.parse import urlparse as _urlparse
            _host = _urlparse(abs_url).hostname or ''
            if allowed_upstream and _host not in allowed_upstream:
                out_lines.append('# blocked: forbidden upstream host')
                continue
            # Always proxy both absolute and relative URLs
            if line.startswith('http://') or line.startswith('https://'):
                # Absolute URL: decide if it is a playlist or media segment
                if line.lower().endswith('.m3u8'):
                    from urllib.parse import quote
                    out_lines.append(f"/api/live/proxy/{slug}/manifest/?tenant={tenant}&url=" + quote(line, safe=''))
                else:
                    # Build seg proxy with base=<dir> and path=<filename>
                    from urllib.parse import quote
                    try:
                        base_abs = line.rsplit('/', 1)[0] + '/'
                        fname = line.rsplit('/', 1)[1]
                        out_lines.append(f"/api/live/proxy/{slug}/seg/" + quote(fname) + f"?tenant={tenant}&base=" + quote(base_abs, safe=''))
                    except Exception:
                        # fallback: pass through if split fails
                        out_lines.append(line)
            else:
                from urllib.parse import quote
                # Relative reference: determine if it's a playlist or a media segment
                if line.lower().endswith('.m3u8'):
                    full = LiveProxyBase._join_url(base, line)
                    out_lines.append(f"/api/live/proxy/{slug}/manifest/?tenant={tenant}&url=" + quote(full, safe=''))
                else:
                    # Keep extension at end of URL (no trailing slash) for HLS clients
                    out_lines.append(f"/api/live/proxy/{slug}/seg/" + quote(line) + f"?tenant={tenant}&base=" + quote(base))
        out = "\n".join(out_lines)
        res = HttpResponse(out, content_type='application/vnd.apple.mpegurl')
        # Do not cache manifests; origin rotates URLs frequently
        res['Cache-Control'] = 'no-store, no-cache, must-revalidate, max-age=0'
        res['Pragma'] = 'no-cache'
        res['Expires'] = '0'
        # CORS for defensive playback
        res['Access-Control-Allow-Origin'] = '*'
        return res


class LiveProxySegmentView(APIView):
    permission_classes = [permissions.AllowAny]
    throttle_classes: list = []  # disable throttling for proxy segments

    def get(self, request, slug: str, path: str):
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        # Validate previewable and fetch meta for allowlist
        obj = get_object_or_404(
            Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug, is_previewable=True)
        )
        # Derive allowlist
        meta = getattr(Live.objects.only('meta').get(tenant=tenant, channel__id_slug=slug), 'meta', None) or {}
        allowed_upstream = set(meta.get('allowed_upstream') or [])
        if not allowed_upstream:
            allowed_upstream = {'edge.novastream.et'}
        base = request.GET.get('base') or ''
        if not base:
            return HttpResponse('# Missing base', status=400, content_type='text/plain')
        upstream = LiveProxyBase._join_url(base, path)
        # Enforce upstream allowlist
        from urllib.parse import urlparse as _urlparse
        _host = _urlparse(upstream).hostname or ''
        if allowed_upstream and _host not in allowed_upstream:
            return HttpResponse('# Forbidden upstream host', status=403, content_type='text/plain')
        try:
            # Forward Range for seek/LL-HLS
            range_header = request.META.get('HTTP_RANGE')
            extra = {'Range': range_header} if range_header else None
            resp = LiveProxyBase._http_get(upstream, stream=True, extra_headers=extra)
        except Exception as exc:
            return HttpResponse(f"# Proxy error: {exc}", status=502, content_type='text/plain')
        # Stream bytes with original content-type when possible; pass through status
        ct = resp.headers.get('Content-Type', 'application/octet-stream')
        from django.http import StreamingHttpResponse
        status_code = resp.status_code
        if status_code not in (200, 206):
            # return concise error so players/reporters see the true upstream status
            return HttpResponse(f"# Upstream error {status_code}", status=status_code, content_type='text/plain')
        sres = StreamingHttpResponse(resp.iter_content(chunk_size=64 * 1024), content_type=ct, status=status_code)
        # long-lived caching for segments
        sres['Cache-Control'] = 'public, max-age=31536000, immutable'
        # Propagate useful headers
        for _h in ('Content-Range', 'Accept-Ranges', 'ETag', 'Last-Modified', 'Content-Length', 'Cache-Control'):
            _v = resp.headers.get(_h)
            if _v:
                sres[_h] = _v
        if 'Accept-Ranges' not in sres:
            sres['Accept-Ranges'] = 'bytes'
        # CORS for defensive playback
        sres['Access-Control-Allow-Origin'] = '*'
        return sres
