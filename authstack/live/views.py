from rest_framework import viewsets, permissions, filters, status
from rest_framework.authentication import SessionAuthentication, BasicAuthentication
from rest_framework.response import Response
from rest_framework.views import APIView
from django.shortcuts import get_object_or_404
from django.conf import settings
from django.http import HttpResponse, Http404, StreamingHttpResponse
from django.core import management
import json
from django.middleware.csrf import get_token
from django.core.cache import cache
from urllib.parse import urlencode
from urllib.request import Request, urlopen
from urllib.error import URLError, HTTPError
from django.urls import reverse

from .models import Live, LiveRadio
from .serializers import LiveSerializer, LiveRadioSerializer

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


class LiveViewSet(viewsets.ModelViewSet):
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
        try:
            is_admin_fe = bool(getattr(user, 'is_superuser', False)) or user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin_fe = bool(getattr(user, 'is_superuser', False))
        if not (is_admin_fe or user.has_perm('live.change_live')):
            qs = qs.filter(is_active=True)
        tenant = self.request.headers.get('X-Tenant-Id') or self.request.query_params.get('tenant') or 'ontime'
        qs = qs.filter(tenant=tenant)
        # Optional filter by channel slug
        ch = self.request.query_params.get('channel')
        if ch:
            qs = qs.filter(channel__id_slug=ch)
        return qs

    def perform_create(self, serializer):
        tenant = self.request.headers.get('X-Tenant-Id') or self.request.query_params.get('tenant') or 'ontime'
        serializer.save(tenant=tenant, added_by=self.request.user)

    def perform_update(self, serializer):
        # Prevent tenant drift
        tenant = self.request.headers.get('X-Tenant-Id') or self.request.query_params.get('tenant') or 'ontime'
        serializer.save(tenant=tenant)

    def get_permissions(self):
        # Writes require staff or change permission; reads require auth
        if self.action in {'create', 'update', 'partial_update', 'destroy'}:
            return [permissions.IsAuthenticated(), permissions.DjangoModelPermissions()]
        return super().get_permissions()


class LiveBySlugView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @swagger_auto_schema(manual_parameters=[LiveViewSet.PARAM_TENANT])
    def get(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.query_params.get('tenant') or 'ontime'
        qs = Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug)
        try:
            is_admin_fe = bool(getattr(request.user, 'is_superuser', False)) or request.user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin_fe = bool(getattr(request.user, 'is_superuser', False))
        if not (is_admin_fe or request.user.has_perm('live.change_live')):
            qs = qs.filter(is_active=True)
        obj = get_object_or_404(qs)
        return Response(LiveSerializer(obj, context={'request': request}).data)


class LiveRadioViewSet(viewsets.ModelViewSet):
    queryset = LiveRadio.objects.all()
    serializer_class = LiveRadioSerializer
    permission_classes = [permissions.IsAuthenticated]
    filter_backends = [filters.SearchFilter, filters.OrderingFilter]
    search_fields = ['name', 'slug', 'country', 'language']
    ordering_fields = ['updated_at', 'priority', 'name']

    @swagger_auto_schema(manual_parameters=[LiveViewSet.PARAM_TENANT])
    def list(self, request, *args, **kwargs):
        return super().list(request, *args, **kwargs)

    def get_queryset(self):
        qs = super().get_queryset()
        tenant = self.request.headers.get('X-Tenant-Id') or self.request.query_params.get('tenant') or 'ontime'
        qs = qs.filter(tenant=tenant)
        # Non-admins see only active & verified
        try:
            is_admin_fe = bool(getattr(self.request.user, 'is_superuser', False)) or self.request.user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin_fe = bool(getattr(self.request.user, 'is_superuser', False))
        if not (is_admin_fe or self.request.user.has_perm('live.change_liveradio')):
            qs = qs.filter(is_active=True, is_verified=True)
        return qs

    def perform_create(self, serializer):
        tenant = self.request.headers.get('X-Tenant-Id') or self.request.query_params.get('tenant') or 'ontime'
        serializer.save(tenant=tenant, added_by=self.request.user if hasattr(self.serializer_class.Meta.model, 'added_by') else None)

    def perform_update(self, serializer):
        tenant = self.request.headers.get('X-Tenant-Id') or self.request.query_params.get('tenant') or 'ontime'
        serializer.save(tenant=tenant)

    def get_permissions(self):
        if self.action in {'create', 'update', 'partial_update', 'destroy'}:
            return [permissions.IsAuthenticated(), permissions.DjangoModelPermissions()]
        return super().get_permissions()


class RadioListView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @swagger_auto_schema(manual_parameters=[LiveViewSet.PARAM_TENANT])
    def get(self, request):
        tenant = request.headers.get('X-Tenant-Id') or request.query_params.get('tenant') or 'ontime'
        qs = LiveRadio.objects.all().filter(tenant=tenant)
        try:
            is_admin_fe = bool(getattr(request.user, 'is_superuser', False)) or request.user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin_fe = bool(getattr(request.user, 'is_superuser', False))
        if not (is_admin_fe or request.user.has_perm('live.change_liveradio')):
            qs = qs.filter(is_active=True, is_verified=True)
        # Optional filters
        q = request.query_params.get('q')
        if q:
            qs = qs.filter(name__icontains=q)
        country = request.query_params.get('country')
        if country:
            qs = qs.filter(country__iexact=country)
        language = request.query_params.get('language')
        if language:
            qs = qs.filter(language__iexact=language)
        data = LiveRadioSerializer(qs.order_by('priority', 'name'), many=True, context={'request': request}).data
        return Response(data)


class RadioPreviewStreamProxy(APIView):
    """Admin-only stream proxy to bypass browser CORS restrictions for preview.
    Does NOT authenticate to upstream nor cache. Best-effort passthrough.
    """
    permission_classes = [permissions.IsAdminUser]
    authentication_classes = [SessionAuthentication, BasicAuthentication]

    def get(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        obj = get_object_or_404(LiveRadio.objects.filter(tenant=tenant, slug=slug))
        target = obj.stream_url
        if not target:
            raise Http404('No stream URL')

        # If browser sends HEAD, don't contact upstream; return generic OK
        if request.method == 'HEAD':
            resp = HttpResponse('', content_type='audio/mpeg', status=200)
            resp['Cache-Control'] = 'no-store'
            resp['Access-Control-Allow-Origin'] = '*'
            resp['Accept-Ranges'] = 'bytes'
            return resp

        # Upstream GET request (with ICY metadata hint)
        try:
            headers = {
                'User-Agent': 'ontime/preview-proxy',
                'Icy-MetaData': '1',  # hint for shoutcast/icecast
                'Accept': '*/*',
                'Cache-Control': 'no-cache',
                'Connection': 'close',
            }
            # Do NOT forward Range to upstream for live streams; it can stall some servers
            req = Request(target, headers=headers, method='GET')
            upstream = urlopen(req, timeout=20)
        except Exception as e:
            raise Http404(f'Upstream error: {e}')

        status_code = upstream.getcode() or 200
        ctype = upstream.headers.get('Content-Type') or 'audio/mpeg'
        clen = upstream.headers.get('Content-Length')
        cdisp = upstream.headers.get('Content-Disposition')
        crange = upstream.headers.get('Content-Range')
        accept_ranges = upstream.headers.get('Accept-Ranges') or 'bytes'
        icy_meta = upstream.headers.get('icy-metaint') or upstream.headers.get('Icy-MetaInt')

        def _gen():
            try:
                while True:
                    chunk = upstream.read(32768)
                    if not chunk:
                        break
                    yield chunk
            finally:
                try:
                    upstream.close()
                except Exception:
                    pass

        # Force a sane default content type for audio streams
        resp = StreamingHttpResponse(_gen(), content_type=ctype or 'audio/mpeg', status=status_code)
        # Hint: some players like seeing these headers
        resp['Cache-Control'] = 'no-store'
        resp['Access-Control-Allow-Origin'] = '*'
        resp['X-Accel-Buffering'] = 'no'
        if clen:
            resp['Content-Length'] = clen
        if cdisp:
            resp['Content-Disposition'] = cdisp
        if crange:
            resp['Content-Range'] = crange
        if accept_ranges:
            resp['Accept-Ranges'] = accept_ranges
        if icy_meta:
            resp['Icy-MetaInt'] = icy_meta
        return resp


class RadioStreamProxy(APIView):
    """App-facing stream proxy (authenticated users). Helps with iOS ATS and odd ICY servers.
    """
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        obj = get_object_or_404(LiveRadio.objects.filter(tenant=tenant, slug=slug))
        target = obj.stream_url
        if not target:
            raise Http404('No stream URL')

        # Upstream GET request (with ICY metadata hint)
        try:
            headers = {
                'User-Agent': 'ontime/app-proxy',
                # Disable ICY metadata for the app proxy to reduce interleaved metadata
                # which some clients may handle poorly in low-bandwidth conditions.
                'Icy-MetaData': '0',
                'Accept': '*/*',
                'Cache-Control': 'no-cache',
                'Connection': 'close',
            }
            # Do NOT forward Range to upstream for live streams; it can stall some servers
            req = Request(target, headers=headers, method='GET')
            upstream = urlopen(req, timeout=20)
        except Exception as e:
            raise Http404(f'Upstream error: {e}')

        status_code = upstream.getcode() or 200
        ctype = upstream.headers.get('Content-Type') or 'audio/mpeg'
        clen = upstream.headers.get('Content-Length')
        crange = upstream.headers.get('Content-Range')
        accept_ranges = upstream.headers.get('Accept-Ranges') or 'bytes'

        def _gen():
            try:
                while True:
                    chunk = upstream.read(8192)
                    if not chunk:
                        break
                    yield chunk
            finally:
                try:
                    upstream.close()
                except Exception:
                    pass

        # Force a sane default content type for audio streams
        resp = StreamingHttpResponse(_gen(), content_type=ctype or 'audio/mpeg', status=status_code)
        resp['Cache-Control'] = 'no-store'
        resp['Access-Control-Allow-Origin'] = '*'
        resp['X-Accel-Buffering'] = 'no'
        if clen:
            resp['Content-Length'] = clen
        if crange:
            resp['Content-Range'] = crange
        if accept_ranges:
            resp['Accept-Ranges'] = accept_ranges
        return resp

# --- Listen/View tracking endpoints (client heartbeats) ---

def _tenant_from_request(request):
    return request.headers.get('X-Tenant-Id') or request.query_params.get('tenant') or 'ontime'


def _sessions_cache_key(kind: str, tenant: str, slug: str) -> str:
    return f"listen_sessions:{kind}:{tenant}:{slug}"


def _prune_and_update_sessions(kind: str, tenant: str, slug: str, session_id: str, action: str, ttl_seconds: int = 70):
    """
    Maintain an in-cache dict of {session_id: last_seen_epoch} per (kind, tenant, slug).
    - action=start: add/update session, returns (active_count, is_new_session)
    - action=heartbeat: update timestamp if exists, returns (active_count, False)
    - action=stop: remove session, returns (active_count, False)
    """
    import time
    now = int(time.time())
    key = _sessions_cache_key(kind, tenant, slug)
    data = cache.get(key) or {}
    # prune stale
    cutoff = now - ttl_seconds
    data = {sid: ts for sid, ts in data.items() if isinstance(ts, int) and ts >= cutoff}
    is_new = False
    if action == 'start':
        if session_id not in data:
            is_new = True
        data[session_id] = now
    elif action == 'heartbeat':
        if session_id in data:
            data[session_id] = now
    elif action == 'stop':
        if session_id in data:
            data.pop(session_id, None)
    cache.set(key, data, timeout=ttl_seconds)
    return len(data), is_new


class LiveListenStartView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, slug: str):
        tenant = _tenant_from_request(request)
        if not request.data or 'session_id' not in request.data:
            return Response({'error': 'session_id_required'}, status=status.HTTP_400_BAD_REQUEST)
        session_id = str(request.data.get('session_id'))
        obj = get_object_or_404(Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug))
        count, is_new = _prune_and_update_sessions('live', tenant, slug, session_id, 'start')
        # update counts best-effort
        try:
            obj.viewer_count = count
            # increment totals once per session appearance
            if is_new:
                obj.total_views = (obj.total_views or 0) + 1
            obj.save(update_fields=['viewer_count', 'total_views', 'updated_at'])
        except Exception:
            pass
        return Response({'status': 'ok', 'viewer_count': count, 'total_views': obj.total_views})


class LiveListenHeartbeatView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, slug: str):
        tenant = _tenant_from_request(request)
        if not request.data or 'session_id' not in request.data:
            return Response({'error': 'session_id_required'}, status=status.HTTP_400_BAD_REQUEST)
        session_id = str(request.data.get('session_id'))
        obj = get_object_or_404(Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug))
        count, _ = _prune_and_update_sessions('live', tenant, slug, session_id, 'heartbeat')
        try:
            if obj.viewer_count != count:
                obj.viewer_count = count
                obj.save(update_fields=['viewer_count', 'updated_at'])
        except Exception:
            pass
        return Response({'status': 'ok', 'viewer_count': count})


class LiveListenStopView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, slug: str):
        tenant = _tenant_from_request(request)
        if not request.data or 'session_id' not in request.data:
            return Response({'error': 'session_id_required'}, status=status.HTTP_400_BAD_REQUEST)
        session_id = str(request.data.get('session_id'))
        obj = get_object_or_404(Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug))
        count, _ = _prune_and_update_sessions('live', tenant, slug, session_id, 'stop')
        try:
            if obj.viewer_count != count:
                obj.viewer_count = count
                obj.save(update_fields=['viewer_count', 'updated_at'])
        except Exception:
            pass
        return Response({'status': 'ok', 'viewer_count': count})


class RadioListenStartView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, slug: str):
        tenant = _tenant_from_request(request)
        if not request.data or 'session_id' not in request.data:
            return Response({'error': 'session_id_required'}, status=status.HTTP_400_BAD_REQUEST)
        session_id = str(request.data.get('session_id'))
        obj = get_object_or_404(LiveRadio.objects.filter(tenant=tenant, slug=slug))
        count, is_new = _prune_and_update_sessions('radio', tenant, slug, session_id, 'start')
        try:
            obj.listener_count = count
            if is_new:
                obj.total_listens = (obj.total_listens or 0) + 1
            obj.save(update_fields=['listener_count', 'total_listens', 'updated_at'])
        except Exception:
            pass
        return Response({'status': 'ok', 'listener_count': count, 'total_listens': obj.total_listens})


class RadioListenHeartbeatView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, slug: str):
        tenant = _tenant_from_request(request)
        if not request.data or 'session_id' not in request.data:
            return Response({'error': 'session_id_required'}, status=status.HTTP_400_BAD_REQUEST)
        session_id = str(request.data.get('session_id'))
        obj = get_object_or_404(LiveRadio.objects.filter(tenant=tenant, slug=slug))
        count, _ = _prune_and_update_sessions('radio', tenant, slug, session_id, 'heartbeat')
        try:
            if obj.listener_count != count:
                obj.listener_count = count
                obj.save(update_fields=['listener_count', 'updated_at'])
        except Exception:
            pass
        return Response({'status': 'ok', 'listener_count': count})


class RadioListenStopView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def post(self, request, slug: str):
        tenant = _tenant_from_request(request)
        if not request.data or 'session_id' not in request.data:
            return Response({'error': 'session_id_required'}, status=status.HTTP_400_BAD_REQUEST)
        session_id = str(request.data.get('session_id'))
        obj = get_object_or_404(LiveRadio.objects.filter(tenant=tenant, slug=slug))
        count, _ = _prune_and_update_sessions('radio', tenant, slug, session_id, 'stop')
        try:
            if obj.listener_count != count:
                obj.listener_count = count
                obj.save(update_fields=['listener_count', 'updated_at'])
        except Exception:
            pass
        return Response({'status': 'ok', 'listener_count': count})


class RadioBySlugView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    @swagger_auto_schema(manual_parameters=[LiveViewSet.PARAM_TENANT])
    def get(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.query_params.get('tenant') or 'ontime'
        qs = LiveRadio.objects.filter(tenant=tenant, slug=slug)
        try:
            is_admin_fe = bool(getattr(request.user, 'is_superuser', False)) or request.user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin_fe = bool(getattr(request.user, 'is_superuser', False))
        if not (is_admin_fe or request.user.has_perm('live.change_liveradio')):
            qs = qs.filter(is_active=True, is_verified=True)
        obj = get_object_or_404(qs)
        return Response(LiveRadioSerializer(obj, context={'request': request}).data)


class RadioSearchView(APIView):
    permission_classes = [permissions.IsAuthenticated]

    def get(self, request):
        # Proxy to radio-browser.info with basic caching
        base = 'https://api.radio-browser.info/json/stations/search'
        name = request.query_params.get('q') or request.query_params.get('name') or ''
        params = {
            'name': name,
        }
        # Optional filters
        country = request.query_params.get('country')
        if country:
            params['country'] = country
        language = request.query_params.get('language')
        if language:
            params['language'] = language
        tag = request.query_params.get('tag')
        if tag:
            params['tag'] = tag

        # Pagination (client-side for proxy): fetch many, then slice
        page = max(1, int(request.query_params.get('page', 1)))
        page_size = min(50, max(1, int(request.query_params.get('page_size', 20))))

        query = urlencode(params)
        target_url = f"{base}?{query}"
        cache_key = f"radio_search:{target_url}"
        cached = cache.get(cache_key)
        if cached is None:
            try:
                req = Request(target_url, headers={'User-Agent': 'ontime/1.0 (admin@ontime)'} )
                with urlopen(req, timeout=8) as resp:
                    body = resp.read().decode('utf-8')
                    data = json.loads(body)
            except (HTTPError, URLError, TimeoutError, ValueError) as e:
                return Response({'error': 'upstream_error', 'detail': str(e)}, status=status.HTTP_502_BAD_GATEWAY)
            cache.set(cache_key, data, timeout=getattr(settings, 'RADIO_SEARCH_CACHE_TTL', 600))
            cached = data
        data = cached or []

        # Normalize minimal fields and slice for pagination
        start = (page - 1) * page_size
        end = start + page_size
        items = []
        for row in data[start:end]:
            items.append({
                'stationuuid': row.get('stationuuid'),
                'name': row.get('name'),
                'country': row.get('country'),
                'language': row.get('language'),
                'bitrate': row.get('bitrate'),
                'tags': row.get('tags'),
                'favicon': row.get('favicon'),
                'url': row.get('url'),
                'url_resolved': row.get('url_resolved'),
                'lastcheckok': row.get('lastcheckok'),
                'lastcheckoktime': row.get('lastcheckoktime'),
            })
        return Response({
            'count': len(data),
            'page': page,
            'page_size': page_size,
            'results': items,
        })


class RadioPreviewView(APIView):
    permission_classes = [permissions.IsAdminUser]
    authentication_classes = [SessionAuthentication, BasicAuthentication]

    def get(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        obj = get_object_or_404(LiveRadio.objects.filter(tenant=tenant, slug=slug))
        # Use admin-only proxy to avoid browser CORS/mixed-content issues
        base = request.build_absolute_uri(reverse('radio-preview-stream', args=[slug]))
        sep = '&' if ('?' in base) else '?'
        proxied = f"{base}{sep}tenant={tenant}"
        url = proxied
        title = obj.name
        last_ok = "Yes" if obj.last_check_ok else ("No" if obj.last_check_ok is not None else "Unknown")
        last_at = obj.last_check_at.isoformat() if obj.last_check_at else "—"
        last_err = obj.last_error or ""
        active = "Yes" if obj.is_active else "No"
        verified = "Yes" if obj.is_verified else "No"
        html_tmpl = """
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Radio Preview: __TITLE__</title>
  <style>
    :root{ --bg:#0f0f11; --fg:#eee; --muted:#bbb; --card:#151517; --border:rgba(255,255,255,.06); --pri:#2d6cdf }
    body{ margin:0; background:var(--bg); color:var(--fg); font-family:system-ui,-apple-system,Segoe UI,Roboto }
    .wrap{ max-width:960px; margin:0 auto; padding:16px }
    .row{ display:flex; gap:16px; align-items:flex-start; flex-wrap:wrap }
    .col{ flex:1 1 360px }
    .card{ background:var(--card); border:1px solid var(--border); border-radius:12px; padding:14px }
    .h{ margin:0 0 10px; font-size:1.1rem }
    .muted{ color:var(--muted); font-size:.9rem; word-break:break-all }
    .btn{ background:var(--pri); color:#fff; border:0; border-radius:8px; padding:8px 12px; cursor:pointer }
    .btn.alt{ background:#39414d }
    .grid{ display:grid; grid-template-columns:140px 1fr; gap:8px 12px; align-items:center }
    .logs{ margin-top:10px; max-height:40vh; overflow:auto; font:12px ui-monospace,Menlo,Consolas; background:#0b0b0c; border:1px solid var(--border); border-radius:8px; padding:8px }
    .controls{ display:flex; gap:8px; align-items:center; flex-wrap:wrap; margin-top:10px }
    input[type=range]{ width:160px }
    code{ background:#0b0b0c; border:1px solid var(--border); border-radius:6px; padding:2px 6px }
    .diag{ margin-top:12px }
    .diag .k{ color:var(--muted) }
  </style>
  <script>
    function addLog(m){
      const el = document.getElementById('logs');
      const d = document.createElement('div');
      d.textContent = '['+new Date().toLocaleTimeString()+'] '+String(m);
      el.appendChild(d); el.scrollTop = el.scrollHeight;
    }
    function probe(url){ /* removed to avoid CORS noise in console */ }
    function getCookie(name){
      const v = '; ' + document.cookie;
      const parts = v.split('; ' + name + '=');
      if (parts.length === 2) return parts.pop().split(';').shift();
    }
    document.addEventListener('DOMContentLoaded', ()=>{
      const audio = document.getElementById('audio');
      const playBtn = document.getElementById('playBtn');
      const muteBtn = document.getElementById('muteBtn');
      const vol = document.getElementById('vol');
      const stateEl = document.getElementById('state');
      const srcEl = document.getElementById('src');
      const copyBtn = document.getElementById('copyBtn');
      const hcBtn = document.getElementById('hcBtn');
      const diagOk = document.getElementById('diag_ok');
      const diagAt = document.getElementById('diag_at');
      const diagErr = document.getElementById('diag_err');
      const diagAct = document.getElementById('diag_active');
      const diagVer = document.getElementById('diag_verified');
      const url = srcEl.dataset.url;

      function reportState(){
        const rs = audio.readyState; const ns = audio.networkState;
        addLog('state: readyState=' + rs + ' networkState=' + ns);
      }

      playBtn.addEventListener('click', ()=>{
        if (audio.paused) {
          audio.play().then(()=>addLog('play resolved')).catch(e=>addLog('play rejected: '+e));
        } else {
          audio.pause(); addLog('paused');
        }
      });
      muteBtn.addEventListener('click', ()=>{ audio.muted = !audio.muted; muteBtn.textContent = audio.muted ? 'Unmute' : 'Mute'; });
      vol.addEventListener('input', ()=>{ audio.volume = Number(vol.value); });
      copyBtn.addEventListener('click', async ()=>{ try { await navigator.clipboard.writeText(url); addLog('copied stream URL'); } catch(e) { addLog('copy failed: '+e); } });

      hcBtn.addEventListener('click', async ()=>{
        try {
          const csrftoken = getCookie('csrftoken');
          const res = await fetch(window.location.href, { method:'POST', headers: { 'Content-Type':'application/json', 'X-CSRFToken': csrftoken || '' }, body: JSON.stringify({ action:'health_check' }) });
          const data = await res.json();
          addLog('health check: '+ (data.status || res.status));
          if (data && data.radio) {
            diagOk.textContent = data.radio.last_check_ok ? 'Yes' : 'No';
            diagAt.textContent = data.radio.last_check_at || '—';
            diagErr.textContent = data.radio.last_error || '';
            diagAct.textContent = data.radio.is_active ? 'Yes' : 'No';
            diagVer.textContent = data.radio.is_verified ? 'Yes' : 'No';
          }
        } catch(e) { addLog('health check failed: '+e); }
      });

      audio.addEventListener('playing', ()=> addLog('AUDIO playing'));
      audio.addEventListener('pause', ()=> addLog('AUDIO pause'));
      audio.addEventListener('stalled', ()=> addLog('AUDIO stalled'));
      audio.addEventListener('error', ()=> addLog('AUDIO error'));
      audio.addEventListener('loadedmetadata', reportState);
      audio.addEventListener('canplay', reportState);

      // initial report only (no cross-origin probe to avoid CORS warnings)
      reportState();
    });
  </script>
</head>
<body>
  <div class="wrap">
    <h3 style="margin:4px 0 12px">Radio Preview: __TITLE__</h3>
    <div class="row">
      <div class="col">
        <div class="card">
          <div class="grid">
            <div>Source</div>
            <div id="src" class="muted" data-url="__URL__"><code>__URL__</code></div>
            <div>Controls</div>
            <div class="controls">
              <button id="playBtn" class="btn">Play / Pause</button>
              <button id="muteBtn" class="btn alt">Mute</button>
              <label style="display:inline-flex;align-items:center;gap:6px">Vol <input id="vol" type="range" min="0" max="1" step="0.01" value="1" /></label>
              <button id="copyBtn" class="btn alt">Copy URL</button>
            </div>
            <div>Player</div>
            <div><audio id="audio" controls preload="auto" src="__URL__"></audio></div>
          </div>
          <div class="diag">
            <div class="grid">
              <div class="k">Active</div><div id="diag_active">__ACTIVE__</div>
              <div class="k">Verified</div><div id="diag_verified">__VERIFIED__</div>
              <div class="k">Last OK</div><div id="diag_ok">__LAST_OK__</div>
              <div class="k">Last Check</div><div id="diag_at">__LAST_AT__</div>
              <div class="k">Last Error</div><div id="diag_err">__LAST_ERR__</div>
            </div>
            <div class="controls"><button id="hcBtn" class="btn">Run Health Check</button></div>
          </div>
          <div class="logs" id="logs"></div>
        </div>
      </div>
    </div>
  </div>
</body>
</html>
"""
        html = (
            html_tmpl
            .replace("__TITLE__", title or "")
            .replace("__URL__", url or "")
            .replace("__ACTIVE__", active)
            .replace("__VERIFIED__", verified)
            .replace("__LAST_OK__", last_ok)
            .replace("__LAST_AT__", last_at)
            .replace("__LAST_ERR__", last_err)
        )
        return HttpResponse(html)

    def post(self, request, slug: str):
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        obj = get_object_or_404(LiveRadio.objects.filter(tenant=tenant, slug=slug))
        try:
            management.call_command(
                "check_radio_health",
                tenant=tenant,
                slug=obj.slug,
                set_verified_on_pass=True,
                set_inactive_on_fail=True,
                verbosity=0,
            )
        except Exception as e:
            pass
        # Reload
        obj.refresh_from_db()
        data = {
            "status": "ok",
            "radio": {
                "slug": obj.slug,
                "last_check_ok": bool(obj.last_check_ok) if obj.last_check_ok is not None else None,
                "last_check_at": obj.last_check_at.isoformat() if obj.last_check_at else None,
                "last_error": obj.last_error or "",
                "is_active": bool(obj.is_active),
                "is_verified": bool(obj.is_verified),
            }
        }
        return Response(data)

class LivePreviewView(APIView):
    """Serve a minimal HTML page that plays the live HLS/DASH using hls.js (for HLS) or native.

    This is intended for quick manual preview in a browser. It does not require authentication,
    but only serves streams where is_previewable=True. It does NOT proxy the media; the browser
    will request the manifest/segments directly from the CDN defined in playback_url.
    """
    permission_classes = [permissions.IsAdminUser]
    authentication_classes = [SessionAuthentication, BasicAuthentication]
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
<html lang="en">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Preview: __TITLE__</title>

  <style>
    :root{
      --bg:#0f0f11; --panel:#151517; --muted:#bfc3c7; --accent:#2d6cdf; --danger:#ff6666;
      --mono: ui-monospace, SFMono-Regular, Menlo, Monaco, "Roboto Mono", "Segoe UI Mono";
    }
    html,body{height:100%; margin:0; background:var(--bg); color:#eee; font-family: system-ui, -apple-system, "Segoe UI", Roboto, Ubuntu, "Helvetica Neue", Arial;}
    header{position:sticky; top:0; z-index:10; background:linear-gradient(180deg,#121214, #151517); padding:12px 16px; border-bottom:1px solid rgba(255,255,255,0.03); display:flex; align-items:center; gap:12px;}
    header h1{font-size:15px; margin:0; font-weight:600;}
    header .sub{font-size:12px; color:var(--muted); margin-left:6px;}
    main{padding:16px; max-width:1100px; margin:0 auto; box-sizing:border-box;}
    .player-wrap{display:grid; grid-template-columns: 1fr 320px; gap:16px;}
    @media (max-width:960px){ .player-wrap{grid-template-columns:1fr;}}
    .card{background:var(--panel); border:1px solid rgba(255,255,255,0.03); padding:12px; border-radius:10px;}
    video{width:100%; height: calc(50vh); max-height:70vh; background:#000; display:block; border-radius:8px; outline:0;}
    .controls{display:flex; gap:8px; flex-wrap:wrap; align-items:center; margin-top:8px;}
    .btn{background:var(--accent); color:#fff; border:0; padding:8px 12px; border-radius:8px; cursor:pointer; font-weight:600;}
    .btn.ghost{background:transparent; border:1px solid rgba(255,255,255,0.06); color:var(--muted); font-weight:500;}
    .btn.warn{background:var(--danger);}
    .meta{font-size:13px; color:var(--muted); margin-top:8px; word-break:break-all;}
    .logs{margin-top:12px; padding:10px; background:#0b0b0c; border:1px solid rgba(255,255,255,0.03); border-radius:8px; max-height:28vh; overflow:auto; font-family:var(--mono); font-size:12px; color:#d4d4d4;}
    .right-col{display:flex; flex-direction:column; gap:10px;}
    label.select-label{display:block; font-size:12px; color:var(--muted); margin-bottom:6px;}
    select, input[type="text"]{width:100%; padding:8px 10px; border-radius:8px; border:1px solid rgba(255,255,255,0.03); background:transparent; color:#eee; font-size:13px; outline:none;}
    .stat-row{display:flex; justify-content:space-between; gap:8px; align-items:center; font-size:13px; color:var(--muted);}
    .small{font-size:12px; color:var(--muted);}
    a.inline-link{color:var(--accent); text-decoration:none; font-weight:600;}
  </style>

  <script src="https://cdn.jsdelivr.net/npm/hls.js@1.5.10/dist/hls.min.js"></script>

  <script>
    // CSRF helper (for same-origin POST)
    function getCookie(name) {
      const value = `; ${document.cookie}`;
      const parts = value.split(`; ${name}=`);
      if (parts.length === 2) return parts.pop().split(';').shift();
    }
    // Replace placeholders __URL__ and __TITLE__ when injecting server-side
    const SRC = '__URL__';
    const TITLE = '__TITLE__';

    function addLog(msg, kind = 'info') {
      const el = document.getElementById('logs');
      const p = document.createElement('div');
      const ts = new Date().toLocaleTimeString();
      p.textContent = '[' + ts + '] ' + String(msg);
      p.className = 'log-' + kind;
      el.appendChild(p);
      el.scrollTop = el.scrollHeight;
    }

    document.addEventListener('DOMContentLoaded', () => {
      const video = document.getElementById('player');
      const playBtn = document.getElementById('playBtn');
      const unmuteBtn = document.getElementById('unmuteBtn');
      const copyBtn = document.getElementById('copyBtn');
      const retryBtn = document.getElementById('retryBtn');
      const qualitySel = document.getElementById('quality');
      const qualitiesText = document.getElementById('qualitiesText');
      const statsToggle = document.getElementById('statsToggle');
      const saveBtn = document.getElementById('saveBtn');
      const detectedBox = document.getElementById('detectedBox');
      const detectedPayloadEl = document.getElementById('detectedPayload');
      const errBox = document.getElementById('err');
      const urlInput = document.getElementById('urlInput');
      let hls = null;
      let manifestLevels = [];
      let statsEnabled = false;

      urlInput.value = SRC;
      document.getElementById('title').textContent = TITLE || 'Untitled';
      document.getElementById('source').textContent = SRC;

      const appendStats = (text) => {
        if (!statsEnabled) return;
        const s = document.getElementById('stats');
        const t = document.createElement('div');
        t.textContent = text;
        s.appendChild(t);
        if (s.scrollHeight > s.clientHeight) s.scrollTop = s.scrollHeight;
      };

      function cleanup() {
        try {
          if (hls) {
            hls.destroy();
            hls = null;
          } else {
            video.pause();
            video.removeAttribute('src');
            video.load();
          }
        } catch(e){ console.warn('cleanup failed', e); }
      }

      function init(source) {
        errBox.textContent = '';
        addLog('Initializing preview for: ' + source);
        cleanup();

        const forceHls = true; // use hls.js for better control over events & quality
        if (!forceHls && video.canPlayType('application/vnd.apple.mpegurl')) {
          addLog('Native HLS supported — using native playback');
          video.src = source;
          video.play().catch(e => addLog('play() rejected (native): ' + e, 'error'));
          return;
        }

        if (window.Hls && Hls.isSupported()) {
          hls = new Hls({
            enableWorker: true,
            lowLatencyMode: false,
            debug: false,
            maxBufferLength: 60,
            maxBufferSize: 50 * 1000 * 1000,
            liveSyncDurationCount: 3,
            maxLiveSyncPlaybackRate: 1.0
          });

          hls.on(Hls.Events.MEDIA_ATTACHED, () => addLog('HLS MEDIA_ATTACHED'));
          hls.on(Hls.Events.MANIFEST_LOADING, () => addLog('HLS MANIFEST_LOADING'));
          hls.on(Hls.Events.MANIFEST_PARSED, (evt, data) => {
            addLog('HLS MANIFEST_PARSED — levels: ' + (data && data.levels ? data.levels.length : 'n/a'));
            manifestLevels = (data && data.levels) ? data.levels : [];
            // populate quality selector
            populateQuality();
            // update detected payload UI
            updateDetected();
          });
          hls.on(Hls.Events.LEVEL_LOADING, (e, d) => addLog('LEVEL_LOADING: ' + (d && d.level)));
          hls.on(Hls.Events.LEVEL_LOADED, (e, d) => addLog('LEVEL_LOADED'));
          hls.on(Hls.Events.FRAG_LOADING, (e, d) => addLog('FRAG_LOADING: ' + (d && d.frag ? d.frag.sn : '')));
          hls.on(Hls.Events.FRAG_LOADED, () => appendStats('frag loaded'));
          hls.on(Hls.Events.ERROR, (event, data) => {
            const fatal = data && data.fatal;
            addLog('HLS ERROR: type=' + (data && data.type) + ' details=' + (data && data.details) + ' fatal=' + fatal, 'error');
            if (fatal) {
              // attempt recovery where safe
              if (data.type === Hls.ErrorTypes.NETWORK_ERROR) {
                addLog('Network error: trying to recover');
                hls.startLoad();
              } else if (data.type === Hls.ErrorTypes.MEDIA_ERROR) {
                addLog('Media error: trying to recoverMediaError()');
                hls.recoverMediaError();
              } else {
                addLog('Fatal error, destroying and showing retry.');
                cleanup();
                errBox.textContent = 'Fatal stream error — use Retry.';
              }
            }
          });

          try {
            hls.loadSource(source);
            hls.attachMedia(video);
          } catch (e) {
            addLog('Failed to attach hls: ' + e, 'error');
            errBox.textContent = 'Failed to start player';
            return;
          }

          hls.on(Hls.Events.LEVEL_SWITCHED, (ev, data) => {
            appendStats('level switched -> ' + (data && data.level));
            updateDetected();
          });

        } else {
          addLog('hls.js not supported in this browser', 'error');
          errBox.textContent = 'Your browser does not support HLS playback.';
        }

        video.addEventListener('playing', () => addLog('VIDEO playing'));
        video.addEventListener('pause', () => addLog('VIDEO pause'));
        video.addEventListener('waiting', () => addLog('VIDEO waiting'));
        video.addEventListener('stalled', () => addLog('VIDEO stalled'));
        video.addEventListener('error', (ev) => {
          addLog('VIDEO element error: ' + ev.type, 'error');
        });

        // small periodic stats when enabled
        let statsInterval = null;
        clearInterval(statsInterval);
        statsInterval = setInterval(() => {
          if (!hls) return;
          const level = hls.currentLevel;
          const bw = (hls.bandwidthEstimate || 0);
          const levelInfo = (manifestLevels[level] || {});
          appendStats('level=' + level + ' bitrate=' + (levelInfo.bitrate||'n/a') + ' estBW=' + Math.round(bw));
        }, 4000);
      }

      function populateQuality(){
        qualitySel.innerHTML = '';
        const opt = document.createElement('option');
        opt.value = '-1';
        opt.textContent = 'Auto';
        qualitySel.appendChild(opt);
        const names = [];
        manifestLevels.forEach((lv, idx) => {
          const o = document.createElement('option');
          const bw = Math.round((lv.bitrate||0)/1000);
          const height = (lv && typeof lv.height === 'number' && lv.height > 0) ? lv.height : null;
          const label = height ? (height + 'p') : ('Level ' + idx);
          o.value = String(idx);
          o.textContent = label + ' — ' + (bw ? (bw + ' kbps') : '');
          qualitySel.appendChild(o);
          names.push(label);
        });
        if (qualitiesText) { qualitiesText.textContent = names.length ? names.join(', ') : 'Single-bitrate or unknown variants'; }
      }

      function buildPayload(){
        const heights = manifestLevels.map(lv => lv && lv.height).filter(h => !!h).sort((a,b)=>b-a);
        const bitrates = manifestLevels.map(lv => lv && lv.bitrate).filter(b => !!b).sort((a,b)=>b-a);
        return {
          stream_type: 'HLS',
          is_verified: true,
          max_height: heights[0] || null,
          max_bitrate: bitrates[0] || null,
          qualities: manifestLevels.map((lv, idx) => ({
            index: idx,
            height: lv && lv.height || null,
            bitrate: lv && lv.bitrate || null,
          })),
        };
      }

      function updateDetected(){
        if (!detectedPayloadEl) return;
        try {
          const payload = buildPayload();
          detectedPayloadEl.textContent = JSON.stringify(payload, null, 2);
          if (detectedBox) detectedBox.style.display = 'block';
        } catch(e) {}
      }

      // Save detected details back to server (admin-only)
      async function saveDetails(){
        try {
          const payload = buildPayload();
          const resp = await fetch(window.location.href, {
            method: 'POST',
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
              'X-CSRFToken': getCookie('csrftoken') || '',
            },
            body: JSON.stringify(payload),
            credentials: 'same-origin',
          });
          if (!resp.ok) throw new Error('HTTP ' + resp.status);
          addLog('Saved details to Live model');
        } catch (e) {
          addLog('Save failed: ' + e, 'error');
        }
      }

      // controls
      playBtn.addEventListener('click', () => {
        if (video.paused) {
          video.play().catch(e => addLog('play() rejected: ' + e, 'error'));
        } else {
          video.pause();
        }
      });

      unmuteBtn.addEventListener('click', () => {
        try { video.muted = false; video.volume = 1; video.play(); addLog('Unmuted'); } catch(e){ addLog('Unmute failed: ' + e, 'error'); }
      });

      copyBtn.addEventListener('click', async () => {
        try {
          await navigator.clipboard.writeText(urlInput.value);
          addLog('Copied URL to clipboard');
        } catch(e) {
          addLog('Copy failed: ' + e, 'error');
        }
      });

      retryBtn.addEventListener('click', () => {
        addLog('Retrying...');
        init(urlInput.value);
      });

      qualitySel.addEventListener('change', () => {
        if (!hls) return;
        const v = parseInt(qualitySel.value, 10);
        if (v === -1) {
          addLog('Switching to Auto quality');
          hls.currentLevel = -1; // -1 = auto
        } else {
          addLog('Switching to level ' + v);
          hls.currentLevel = v;
        }
      });

      statsToggle.addEventListener('click', () => {
        statsEnabled = !statsEnabled;
        document.getElementById('stats').style.display = statsEnabled ? 'block' : 'none';
        statsToggle.textContent = statsEnabled ? 'Hide stats' : 'Show stats';
      });

      // Initialize player now
      if (saveBtn) {
        saveBtn.addEventListener('click', () => {
          addLog('Saving detected details...');
          saveDetails();
        });
      }

      init(SRC);
    });
  </script>
</head>

<body>
  <header>
    <h1 id="title">Preview</h1>
    <div class="sub">HLS preview tool — direct playback & debug</div>
  </header>

  <main>
    <div class="player-wrap">
      <div class="card">
        <video id="player" controls playsinline muted></video>

        <div class="controls" style="margin-top:12px">
          <button id="playBtn" class="btn ghost">Play / Pause</button>
          <button id="unmuteBtn" class="btn">Unmute</button>
          <button id="retryBtn" class="btn ghost">Retry</button>
          <button id="copyBtn" class="btn ghost">Copy URL</button>

          <div style="flex:1"></div>

          <button id="statsToggle" class="btn ghost">Show stats</button>
          <button id="saveBtn" class="btn">Save details</button>
        </div>

        <div class="meta">
          <div class="small">Source: <a id="source" class="inline-link" target="_blank" rel="noopener noreferrer">__URL__</a></div>
        </div>

        <div class="logs card" id="logs" style="margin-top:12px; max-height:220px;"></div>
      </div>

      <aside class="right-col">
        <div class="card">
          <label class="select-label">Stream URL</label>
          <input id="urlInput" type="text" spellcheck="false" />
          <div style="height:8px"></div>

          <label class="select-label">Quality</label>
          <select id="quality">
            <option value="-1">Auto</option>
          </select>
          <div class="small" style="margin-top:6px">Available: <span id="qualitiesText">—</span></div>

          <div style="height:10px"></div>

          <div class="stat-row"><div class="small">Player state</div><div id="state" class="small">—</div></div>
          <div class="stat-row"><div class="small">Browser</div><div class="small" id="ua"></div></div>

          <div style="height:8px"></div>
          <div class="small">Quick actions</div>
          <div style="display:flex; gap:8px; margin-top:8px;">
            <a id="openInNew" class="btn ghost" href="__URL__" target="_blank" rel="noopener noreferrer">Open raw</a>
            <a class="btn ghost" href="#" onclick="location.reload(); return false;">Hard reload</a>
          </div>
        </div>

        <div class="card" id="stats" style="display:none; padding:10px; font-family:var(--mono); font-size:13px;">
          <div class="small" style="margin-bottom:8px">Live stats (updated periodically)</div>
        </div>

        <div class="card" id="detectedBox" style="display:none;">
          <div class="small" style="margin-bottom:8px; color:var(--muted)">Detected details to be saved</div>
          <pre id="detectedPayload" style="margin:0; font-family:var(--mono); font-size:12px; line-height:1.5; white-space:pre-wrap; word-break:break-word;"></pre>
        </div>

        <div class="card">
          <div class="small" style="margin-bottom:8px; color:var(--muted)">Errors</div>
          <div id="err" style="color:var(--danger); font-weight:700"></div>
        </div>
      </aside>
    </div>

    <div style="height:18px"></div>
    <div class="meta card">
      <strong>Notes</strong>
      <ul style="margin:8px 0 0 18px; color:var(--muted)">
        <li>Native HLS on Safari/iOS may ignore custom headers — using hls.js forces JS-based HLS playback.</li>
        <li>If the stream uses expiring tokens (signed URLs), you must request fresh URLs from the origin before playback.</li>
        <li>For audio-only radio, the same HLS playlist works — the video element will handle audio streams.</li>
      </ul>
    </div>
  </main>

  <script>
    // small runtime touches
    try {
      document.getElementById('ua').textContent = navigator.userAgent.split(') ')[0] + ')';
    } catch(e){}
  </script>
</body>
</html>

"""
        html = html.replace('__TITLE__', title).replace('__URL__', url).replace('__SLUG__', slug).replace('__TENANT__', tenant)
        # Ensure CSRF cookie is set so POST from this page can succeed
        try:
            get_token(request)
        except Exception:
            pass
        return HttpResponse(html)

    def post(self, request, slug: str):
        # Admin-only: accept metrics from preview and update the Live entry with basic fields
        tenant = request.headers.get('X-Tenant-Id') or request.GET.get('tenant') or 'ontime'
        qs = Live.objects.select_related('channel').filter(tenant=tenant, channel__id_slug=slug, is_previewable=True)
        obj = get_object_or_404(qs)
        # Prefer DRF's request.data (handles JSON); fallback to raw body parse
        data = None
        try:
            data = request.data
            if data is None or data == '' or (hasattr(data, 'dict') and not data):
                raise ValueError('empty')
        except Exception:
            try:
                body = request.body.decode('utf-8') if request.body else ''
                data = json.loads(body) if body else {}
            except Exception:
                return Response({'error': 'invalid_json'}, status=status.HTTP_400_BAD_REQUEST)

        changed = False
        # Update stream_type
        st = data.get('stream_type')
        if st and obj.stream_type != st:
            obj.stream_type = st
            changed = True
        # Mark verified
        if data.get('is_verified') and not obj.is_verified:
            obj.is_verified = True
            changed = True
        # Resolution
        mh = data.get('max_height')
        if mh and isinstance(mh, int):
            res = f"{mh}p"
            if obj.resolution != res:
                obj.resolution = res
                changed = True
        # Bitrate
        mb = data.get('max_bitrate')
        if mb and isinstance(mb, (int, float)):
            mb_int = int(mb)
            if obj.bitrate != mb_int:
                obj.bitrate = mb_int
                changed = True
        if changed:
            obj.save(update_fields=['stream_type','is_verified','resolution','bitrate','updated_at'])
        return Response({'ok': True, 'updated': changed})


