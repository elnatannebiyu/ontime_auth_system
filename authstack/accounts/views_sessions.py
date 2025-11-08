from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status
from django.utils import timezone
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from django.db.models import Count
from django.db.models.functions import TruncDate
from datetime import timedelta
from .models import UserSession, Membership
from tenants.models import Tenant


class SessionListView(APIView):
    """List all active sessions for the current user"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request):
        # Get all active sessions for the current user
        sessions = UserSession.objects.filter(
            user=request.user,
            is_active=True,
            expires_at__gt=timezone.now()
        ).order_by('-last_activity')
        
        # Get current session identifiers from the access token
        current_access_jti = None
        current_session_id = None
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        if auth_header.startswith('Bearer '):
            try:
                token_str = auth_header.split(' ')[1]
                token = AccessToken(token_str)
                current_access_jti = token.get('jti')
                current_session_id = token.get('session_id')
            except (TokenError, IndexError):
                pass
        
        session_data = []
        for session in sessions:
            session_info = {
                'id': str(session.id),
                'device_id': session.device_id,
                'device_name': session.device_name,
                'device_type': session.device_type,
                'device_info': {
                    'device_name': session.device_name,
                    'device_type': session.device_type,
                    'os_name': session.os_name or 'Unknown',
                    'os_version': session.os_version or '',
                },
                'ip_address': session.ip_address,
                'location': session.location,
                'created_at': session.created_at.isoformat(),
                'last_activity': session.last_activity.isoformat(),
                'is_current': (str(session.id) == str(current_session_id)) if current_session_id else (session.access_token_jti == current_access_jti),
            }
            session_data.append(session_info)
        
        return Response({
            'sessions': session_data,
            'count': len(session_data)
        })


class SessionDetailView(APIView):
    """Get details of a specific session"""
    permission_classes = [IsAuthenticated]
    
    def get(self, request, session_id):
        try:
            session = UserSession.objects.get(
                id=session_id,
                user=request.user,
                is_active=True
            )
            # Extract current token details
            current_access_jti = None
            current_session_id = None
            auth_header = request.META.get('HTTP_AUTHORIZATION', '')
            if auth_header.startswith('Bearer '):
                try:
                    token_str = auth_header.split(' ')[1]
                    token = AccessToken(token_str)
                    current_access_jti = token.get('jti')
                    current_session_id = token.get('session_id')
                except (TokenError, IndexError):
                    pass
            
            return Response({
                'id': str(session.id),
                'device_id': session.device_id,
                'device_name': session.device_name,
                'device_type': session.device_type,
                'ip_address': session.ip_address,
                'location': session.location,
                'user_agent': session.user_agent,
                'created_at': session.created_at.isoformat(),
                'last_activity': session.last_activity.isoformat(),
                'expires_at': session.expires_at.isoformat(),
                'is_current': (str(session.id) == str(current_session_id)) if current_session_id else (session.access_token_jti == current_access_jti),
            })
        except UserSession.DoesNotExist:
            return Response(
                {'error': 'Session not found'},
                status=status.HTTP_404_NOT_FOUND
            )
    
    def delete(self, request, session_id):
        """Revoke a specific session"""
        try:
            session = UserSession.objects.get(
                id=session_id,
                user=request.user,
                is_active=True
            )
            
            # Don't allow revoking current session through this endpoint
            current_jti = getattr(request, 'refresh_jti', None)
            if session.refresh_token_jti == current_jti:
                return Response(
                    {'error': 'Cannot revoke current session. Use logout instead.'},
                    status=status.HTTP_400_BAD_REQUEST
                )
            
            session.revoke(reason='User revoked')
            
            return Response({
                'message': 'Session revoked successfully'
            })
        except UserSession.DoesNotExist:
            return Response(
                {'error': 'Session not found'},
                status=status.HTTP_404_NOT_FOUND
            )


class RevokeAllSessionsView(APIView):
    """Revoke all sessions except the current one"""
    permission_classes = [IsAuthenticated]
    
    def post(self, request):
        current_jti = getattr(request, 'refresh_jti', None)
        # Also try to get current session_id from access token
        current_session_id = None
        auth_header = request.META.get('HTTP_AUTHORIZATION', '')
        if auth_header.startswith('Bearer '):
            try:
                token_str = auth_header.split(' ')[1]
                token = AccessToken(token_str)
                current_session_id = token.get('session_id')
            except (TokenError, IndexError):
                pass
        
        # Revoke all sessions except current
        sessions = UserSession.objects.filter(
            user=request.user,
            is_active=True
        )
        if current_session_id:
            sessions = sessions.exclude(id=current_session_id)
        elif current_jti:
            sessions = sessions.exclude(refresh_token_jti=current_jti)
        
        count = sessions.count()
        for session in sessions:
            session.revoke(reason='User revoked all sessions')
        
        return Response({
            'message': f'Revoked {count} session(s)',
            'revoked_count': count
        })


class AdminSessionsStatsView(APIView):
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        is_admin_fe = False
        try:
            is_admin_fe = user.is_staff or user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin_fe = user.is_staff
        if not is_admin_fe:
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)

        tenant_slug = request.headers.get('X-Tenant-Id') or request.query_params.get('tenant') or 'ontime'
        try:
            tenant = Tenant.objects.get(slug=tenant_slug)
        except Tenant.DoesNotExist:
            return Response({'detail': f'Tenant not found: {tenant_slug}'}, status=status.HTTP_404_NOT_FOUND)

        tenant_user_ids = Membership.objects.filter(tenant=tenant).values_list('user_id', flat=True)
        now = timezone.now()
        qs = UserSession.objects.filter(is_active=True, expires_at__gt=now, user_id__in=tenant_user_ids)

        active_sessions = qs.count()
        active_users = qs.values('user_id').distinct().count()

        since = now - timedelta(days=6)
        buckets = (
            qs.filter(last_activity__date__gte=since.date())
              .annotate(day=TruncDate('last_activity'))
              .values('day')
              .annotate(count=Count('id'))
              .order_by('day')
        )
        by_day = [{'day': b['day'].isoformat(), 'count': b['count']} for b in buckets]

        return Response({
            'tenant': tenant_slug,
            'active_sessions': active_sessions,
            'active_users': active_users,
            'by_day': by_day,
        })


class AdminSessionsListView(APIView):
    """Tenant-scoped sessions list with pagination/search/ordering for AdminFrontend/staff"""
    permission_classes = [IsAuthenticated]

    def get(self, request):
        user = request.user
        try:
            is_admin = user.is_staff or user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin = user.is_staff
        if not is_admin:
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)

        tenant_slug = request.headers.get('X-Tenant-Id') or request.query_params.get('tenant') or 'ontime'
        try:
            tenant = Tenant.objects.get(slug=tenant_slug)
        except Tenant.DoesNotExist:
            return Response({'detail': f'Tenant not found: {tenant_slug}'}, status=status.HTTP_404_NOT_FOUND)

        tenant_user_ids = Membership.objects.filter(tenant=tenant).values_list('user_id', flat=True)
        qs = UserSession.objects.filter(user_id__in=tenant_user_ids)
        qs = qs.select_related('user')

        # Search across user email, device, os, ip
        search = (request.query_params.get('search') or '').strip()
        if search:
            from django.db.models import Q
            qs = qs.filter(
                Q(user__email__icontains=search) |
                Q(device_type__icontains=search) |
                Q(os_name__icontains=search) |
                Q(os_version__icontains=search) |
                Q(ip_address__icontains=search)
            )

        # Ordering whitelist
        ordering = (request.query_params.get('ordering') or '').strip()
        allowed = {'created_at', 'last_activity', 'expires_at', 'is_active', 'user__email', 'device_type', 'os_name', 'ip_address'}
        order_fields = []
        if ordering:
            for raw in ordering.split(','):
                f = raw.strip()
                if not f:
                    continue
                name = f[1:] if f.startswith('-') else f
                if name in allowed:
                    order_fields.append(f)
        if order_fields:
            qs = qs.order_by(*order_fields)
        else:
            qs = qs.order_by('-last_activity')

        total = qs.count()
        # Pagination
        try:
            page = int(request.query_params.get('page') or 1)
        except Exception:
            page = 1
        try:
            page_size = int(request.query_params.get('page_size') or 20)
        except Exception:
            page_size = 20
        page_size = max(1, min(page_size, 100))
        start = (page - 1) * page_size
        end = start + page_size
        items = qs[start:end]

        def row(s: UserSession):
            return {
                'id': str(s.id),
                'user_email': getattr(s.user, 'email', ''),
                'device_type': s.device_type,
                'os_name': s.os_name,
                'os_version': s.os_version,
                'ip_address': s.ip_address,
                'is_active': s.is_active,
                'created_at': s.created_at.isoformat(),
                'last_activity': s.last_activity.isoformat(),
                'expires_at': s.expires_at.isoformat(),
            }

        return Response({
            'results': [row(s) for s in items],
            'count': total,
            'page': page,
            'page_size': page_size,
        })


class AdminSessionRevokeView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request, session_id):
        user = request.user
        try:
            is_admin = user.is_staff or user.groups.filter(name='AdminFrontend').exists()
        except Exception:
            is_admin = user.is_staff
        if not is_admin:
            return Response({'detail': 'Permission denied.'}, status=status.HTTP_403_FORBIDDEN)

        tenant = getattr(request, 'tenant', None)
        if tenant is None:
            return Response({'detail': 'Unknown tenant.'}, status=status.HTTP_400_BAD_REQUEST)

        try:
            s = UserSession.objects.get(id=session_id)
        except UserSession.DoesNotExist:
            return Response({'detail': 'Session not found'}, status=status.HTTP_404_NOT_FOUND)

        # Ensure the session's user belongs to this tenant
        if not Membership.objects.filter(user=s.user, tenant=tenant).exists():
            return Response({'detail': 'Session not in this tenant'}, status=status.HTTP_404_NOT_FOUND)

        if not s.is_active:
            return Response({'detail': 'Session already revoked'}, status=status.HTTP_200_OK)

        s.revoke(reason='Admin revoked')
        return Response({'detail': 'Session revoked'}, status=status.HTTP_200_OK)
