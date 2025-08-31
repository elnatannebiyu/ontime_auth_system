from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from rest_framework import status
from django.utils import timezone
from rest_framework_simplejwt.tokens import AccessToken
from rest_framework_simplejwt.exceptions import TokenError
from .models import UserSession


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
