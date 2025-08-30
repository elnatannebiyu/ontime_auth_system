# Part 3: Refresh Token Rotation

## Overview
Implement secure refresh token rotation with reuse detection to prevent token theft.

## 3.1 Refresh Token View

```python
# accounts/views.py
import hashlib
import uuid
from datetime import timedelta
from django.utils import timezone
from django.core.cache import cache
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from sessions.models import Session
from accounts.serializers import EnhancedTokenObtainPairSerializer

@api_view(['POST'])
@permission_classes([AllowAny])
def refresh_token_view(request):
    """Rotate refresh token with reuse detection"""
    refresh_token = request.data.get('refresh_token')
    
    if not refresh_token:
        return Response({
            'code': 'INVALID_TOKEN',
            'message': 'Refresh token required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Hash token to find session
    token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
    
    try:
        session = Session.objects.get(refresh_token_hash=token_hash)
        
        # Check if session is valid
        if not session.is_valid():
            return Response({
                'code': 'TOKEN_REVOKED',
                'message': 'Session expired or revoked'
            }, status=status.HTTP_401_UNAUTHORIZED)
        
        # Reuse detection - check if this token family is being rotated too quickly
        reuse_key = f'refresh_reuse_{session.refresh_token_family}'
        if cache.get(reuse_key):
            # Token family compromised - revoke all sessions in family
            Session.objects.filter(
                refresh_token_family=session.refresh_token_family
            ).update(
                revoked_at=timezone.now(),
                revoke_reason='reuse_detected'
            )
            
            # Also increment user's token version for extra security
            user = session.user
            user.token_version += 1
            user.save()
            
            return Response({
                'code': 'TOKEN_REVOKED',
                'message': 'Security violation detected. Please sign in again.'
            }, status=status.HTTP_401_UNAUTHORIZED)
        
        # Set reuse detection flag (5 second window)
        cache.set(reuse_key, True, 5)
        
        # Check user status
        user = session.user
        if user.status != 'active':
            return Response({
                'code': 'ACCOUNT_DISABLED',
                'message': _get_status_message(user)
            }, status=status.HTTP_403_FORBIDDEN)
        
        # Rotate the refresh token
        new_refresh_token = session.rotate_token()
        
        # Generate new access token
        refresh = EnhancedTokenObtainPairSerializer.get_token(user)
        access = refresh.access_token
        
        # Add session info to tokens
        access['sid'] = str(session.id)
        access['jti'] = str(uuid.uuid4())
        
        # Update device last seen if attached
        if session.device:
            session.device.last_seen_at = timezone.now()
            session.device.save()
        
        # Clear reuse flag after successful rotation
        cache.delete(reuse_key)
        
        return Response({
            'access': str(access),
            'refresh': new_refresh_token,
            'session_id': str(session.id),
            'expires_in': settings.SIMPLE_JWT['ACCESS_TOKEN_LIFETIME'].total_seconds()
        }, status=status.HTTP_200_OK)
        
    except Session.DoesNotExist:
        return Response({
            'code': 'INVALID_TOKEN',
            'message': 'Invalid refresh token'
        }, status=status.HTTP_401_UNAUTHORIZED)

def _get_status_message(user):
    """Helper to get user status message"""
    if user.status == 'banned':
        return f'Account banned: {user.banned_reason or "Contact support"}'
    elif user.status == 'deleted':
        return 'This account no longer exists'
    elif user.status == 'disabled':
        return 'Account disabled. Contact support.'
    return 'Account not active'
```

## 3.2 Logout View

```python
# accounts/views.py
from rest_framework.permissions import IsAuthenticated

@api_view(['POST'])
@permission_classes([IsAuthenticated])
def logout_view(request):
    """Logout and revoke session"""
    session_id = request.data.get('session_id')
    logout_all = request.data.get('logout_all', False)
    
    user = request.user
    
    if logout_all:
        # Revoke all user sessions
        count = user.sessions.filter(revoked_at__isnull=True).update(
            revoked_at=timezone.now(),
            revoke_reason='user_logout_all'
        )
        message = f'Logged out from {count} devices'
    elif session_id:
        # Revoke specific session
        Session.objects.filter(
            id=session_id,
            user=user,
            revoked_at__isnull=True
        ).update(
            revoked_at=timezone.now(),
            revoke_reason='user_logout'
        )
        message = 'Logged out successfully'
    else:
        # Try to get session from token
        auth = request.headers.get('Authorization', '')
        if auth.startswith('Bearer '):
            import jwt
            token = auth.split(' ')[1]
            try:
                decoded = jwt.decode(token, options={"verify_signature": False})
                sid = decoded.get('sid')
                if sid:
                    Session.objects.filter(
                        id=sid,
                        user=user,
                        revoked_at__isnull=True
                    ).update(
                        revoked_at=timezone.now(),
                        revoke_reason='user_logout'
                    )
            except:
                pass
        message = 'Logged out successfully'
    
    # Clear push token if provided
    push_token = request.data.get('push_token')
    if push_token:
        from sessions.models import Device
        Device.objects.filter(
            user=user,
            push_token=push_token
        ).update(push_token='')
    
    return Response({'message': message}, status=status.HTTP_200_OK)
```

## 3.3 Session Management Views

```python
# accounts/views.py

@api_view(['GET'])
@permission_classes([IsAuthenticated])
def list_sessions_view(request):
    """List all active sessions for current user"""
    sessions = Session.objects.filter(
        user=request.user,
        revoked_at__isnull=True
    ).select_related('device').order_by('-last_used_at')
    
    session_list = []
    for session in sessions:
        session_data = {
            'id': str(session.id),
            'created_at': session.created_at.isoformat(),
            'last_used_at': session.last_used_at.isoformat(),
            'ip_address': session.ip_address,
            'user_agent': session.user_agent,
        }
        
        if session.device:
            session_data['device'] = {
                'platform': session.device.platform,
                'app_version': session.device.app_version,
                'device_name': session.device.device_name,
                'last_seen': session.device.last_seen_at.isoformat(),
            }
        
        # Mark current session
        auth = request.headers.get('Authorization', '')
        if auth.startswith('Bearer '):
            import jwt
            token = auth.split(' ')[1]
            try:
                decoded = jwt.decode(token, options={"verify_signature": False})
                if str(session.id) == decoded.get('sid'):
                    session_data['is_current'] = True
            except:
                pass
        
        session_list.append(session_data)
    
    return Response({
        'sessions': session_list,
        'count': len(session_list)
    }, status=status.HTTP_200_OK)

@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def revoke_session_view(request, session_id):
    """Revoke a specific session"""
    try:
        session = Session.objects.get(
            id=session_id,
            user=request.user
        )
        
        if session.revoked_at:
            return Response({
                'message': 'Session already revoked'
            }, status=status.HTTP_200_OK)
        
        session.revoked_at = timezone.now()
        session.revoke_reason = 'user_revoked'
        session.save()
        
        return Response({
            'message': 'Session revoked successfully'
        }, status=status.HTTP_200_OK)
        
    except Session.DoesNotExist:
        return Response({
            'code': 'NOT_FOUND',
            'message': 'Session not found'
        }, status=status.HTTP_404_NOT_FOUND)
```

## 3.4 Admin Actions

```python
# accounts/admin_views.py
from rest_framework import viewsets
from rest_framework.decorators import action
from rest_framework.permissions import IsAdminUser
from accounts.models import User

class UserAdminViewSet(viewsets.ModelViewSet):
    queryset = User.objects.all()
    permission_classes = [IsAdminUser]
    
    @action(detail=True, methods=['post'])
    def ban(self, request, pk=None):
        """Ban user and revoke all sessions"""
        user = self.get_object()
        reason = request.data.get('reason', '')
        
        user.ban(reason)
        
        return Response({
            'message': f'User {user.username} banned',
            'sessions_revoked': user.sessions.filter(revoked_at__isnull=False).count()
        }, status=status.HTTP_200_OK)
    
    @action(detail=True, methods=['post'])
    def unban(self, request, pk=None):
        """Unban user"""
        user = self.get_object()
        
        user.status = 'active'
        user.banned_reason = ''
        user.save()
        
        return Response({
            'message': f'User {user.username} unbanned'
        }, status=status.HTTP_200_OK)
    
    @action(detail=True, methods=['post'])
    def disable(self, request, pk=None):
        """Disable user account"""
        user = self.get_object()
        
        user.status = 'disabled'
        user.token_version += 1
        user.save()
        user.sessions.update(
            revoked_at=timezone.now(),
            revoke_reason='admin_disabled'
        )
        
        return Response({
            'message': f'User {user.username} disabled'
        }, status=status.HTTP_200_OK)
    
    @action(detail=True, methods=['post'])
    def delete_account(self, request, pk=None):
        """Soft delete user account"""
        user = self.get_object()
        
        user.soft_delete()
        
        return Response({
            'message': f'User {user.username} deleted'
        }, status=status.HTTP_200_OK)
    
    @action(detail=True, methods=['post'])
    def force_logout(self, request, pk=None):
        """Force logout user from all devices"""
        user = self.get_object()
        
        user.revoke_all_sessions()
        
        return Response({
            'message': f'All sessions revoked for {user.username}',
            'token_version': user.token_version
        }, status=status.HTTP_200_OK)
```

## 3.5 Update URLs

```python
# accounts/urls.py
from django.urls import path, include
from rest_framework.routers import DefaultRouter
from . import views, admin_views

router = DefaultRouter()
router.register(r'admin/users', admin_views.UserAdminViewSet)

urlpatterns = [
    path('login/', views.login_view, name='login'),
    path('refresh/', views.refresh_token_view, name='refresh'),
    path('logout/', views.logout_view, name='logout'),
    path('me/', views.current_user_view, name='current_user'),
    path('sessions/', views.list_sessions_view, name='list_sessions'),
    path('sessions/<uuid:session_id>/revoke/', views.revoke_session_view, name='revoke_session'),
    path('', include(router.urls)),
]
```

## 3.6 Cleanup Task

```python
# sessions/tasks.py
from celery import shared_task
from django.utils import timezone
from datetime import timedelta
from sessions.models import Session

@shared_task
def cleanup_expired_sessions():
    """Clean up expired sessions daily"""
    # Delete sessions expired more than 7 days ago
    cutoff = timezone.now() - timedelta(days=7)
    
    deleted_count = Session.objects.filter(
        expires_at__lt=cutoff
    ).delete()[0]
    
    return f'Deleted {deleted_count} expired sessions'

@shared_task
def cleanup_revoked_sessions():
    """Clean up revoked sessions after 30 days"""
    cutoff = timezone.now() - timedelta(days=30)
    
    deleted_count = Session.objects.filter(
        revoked_at__lt=cutoff
    ).delete()[0]
    
    return f'Deleted {deleted_count} old revoked sessions'
```

## Testing

### Test refresh rotation
```bash
# Initial login
curl -X POST http://localhost:8000/api/auth/login/ \
  -H "Content-Type: application/json" \
  -d '{"username": "test", "password": "pass"}'
# Save refresh token

# Refresh token
curl -X POST http://localhost:8000/api/auth/refresh/ \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "YOUR_REFRESH_TOKEN"}'

# Try to reuse old refresh token (should fail)
curl -X POST http://localhost:8000/api/auth/refresh/ \
  -H "Content-Type: application/json" \
  -d '{"refresh_token": "OLD_REFRESH_TOKEN"}'
# Should get TOKEN_REVOKED error
```

### Test session management
```bash
# List sessions
curl -X GET http://localhost:8000/api/auth/sessions/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# Revoke specific session
curl -X DELETE http://localhost:8000/api/auth/sessions/SESSION_ID/revoke/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"

# Logout all
curl -X POST http://localhost:8000/api/auth/logout/ \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"logout_all": true}'
```

## Security Notes

1. **Token Rotation**: Each refresh generates new token, old one invalidated
2. **Reuse Detection**: 5-second window detects token theft attempts
3. **Family Revocation**: Compromised token family gets all tokens revoked
4. **Cleanup**: Automated tasks remove old sessions
5. **Admin Actions**: Admins can force logout users

## Next Steps

✅ Secure refresh token rotation
✅ Reuse detection with family revocation
✅ Session management endpoints
✅ Admin actions for user control
✅ Automated cleanup tasks

Continue to [Part 4: OTP Authentication](./part4-otp-auth.md)
