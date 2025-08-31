from rest_framework import status
from rest_framework.views import APIView
from rest_framework.response import Response
from rest_framework.permissions import IsAuthenticated
from django.utils import timezone
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
        
        # Get current session JTI from request
        current_jti = getattr(request, 'refresh_jti', None)
        
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
                    'os_name': 'Unknown',  # Parse from user_agent if needed
                    'os_version': '',
                },
                'ip_address': session.ip_address,
                'location': session.location,
                'created_at': session.created_at.isoformat(),
                'last_activity': session.last_activity.isoformat(),
                'is_current': session.refresh_token_jti == current_jti,
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
            
            current_jti = getattr(request, 'refresh_jti', None)
            
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
                'is_current': session.refresh_token_jti == current_jti,
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
        
        # Revoke all sessions except current
        sessions = UserSession.objects.filter(
            user=request.user,
            is_active=True
        ).exclude(refresh_token_jti=current_jti)
        
        count = sessions.count()
        for session in sessions:
            session.revoke(reason='User revoked all sessions')
        
        return Response({
            'message': f'Revoked {count} session(s)',
            'revoked_count': count
        })
