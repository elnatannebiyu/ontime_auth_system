"""Version checking and feature flag API views"""
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response
from onchannels.version_service import VersionCheckService
from onchannels.version_models import AppVersion, FeatureFlag
from django.utils import timezone
from django.conf import settings
from onchannels.notification_models import Announcement
from django.db import models


@api_view(['POST'])
@permission_classes([AllowAny])
def check_version_view(request):
    """Check app version and get update info"""
    platform = request.data.get('platform', '').lower()
    version = request.data.get('version', '')
    build_number = request.data.get('build_number')
    
    # Validate input
    if not platform or not version:
        return Response({
            'error': 'Platform and version required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    if platform not in ['ios', 'android', 'web']:
        return Response({
            'error': f'Invalid platform: {platform}'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Check version
    result = VersionCheckService.check_version(platform, version, build_number)
    
    # Add timestamp
    result['checked_at'] = timezone.now().isoformat()
    
    # Add feature flags if user is authenticated
    if request.user.is_authenticated:
        result['features'] = VersionCheckService.get_feature_flags(
            user_id=str(request.user.id),
            platform=platform,
            version=version,
            is_staff=request.user.is_staff
        )
    
    return Response(result, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def get_feature_flags_view(request):
    """Get feature flags for authenticated user"""
    platform = request.GET.get('platform', 'web').lower()
    version = request.GET.get('version', '1.0.0')
    
    flags = VersionCheckService.get_feature_flags(
        user_id=str(request.user.id),
        platform=platform,
        version=version,
        is_staff=request.user.is_staff
    )
    
    return Response({
        'features': flags,
        'user_id': str(request.user.id),
        'platform': platform,
        'version': version
    }, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_latest_version_view(request):
    """Get latest version info for platform"""
    platform = request.GET.get('platform', '').lower()
    
    if not platform:
        return Response({
            'error': 'Platform required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    latest = AppVersion.get_latest_version(platform)
    
    if not latest:
        return Response({
            'error': f'No version found for {platform}'
        }, status=status.HTTP_404_NOT_FOUND)
    
    return Response({
        'platform': platform,
        'version': latest.version,
        'build_number': latest.build_number,
        'released_at': latest.released_at.isoformat(),
        'features': latest.features,
        'changelog': latest.changelog,
        'store_url': _get_store_url_for_response(platform, latest)
    }, status=status.HTTP_200_OK)


@api_view(['GET'])
@permission_classes([AllowAny])
def get_supported_versions_view(request):
    """Get all supported versions for platform"""
    platform = request.GET.get('platform', '').lower()
    
    if not platform:
        # Return all platforms
        versions = AppVersion.objects.filter(
            status__in=['active', 'deprecated']
        ).order_by('platform', '-released_at')
    else:
        versions = AppVersion.objects.filter(
            platform=platform,
            status__in=['active', 'deprecated']
        ).order_by('-released_at')
    
    data = []
    for version in versions:
        data.append({
            'platform': version.platform,
            'version': version.version,
            'status': version.status,
            'released_at': version.released_at.isoformat(),
            'deprecated': version.status == 'deprecated',
            'end_of_support': version.end_of_support_at.isoformat() if version.end_of_support_at else None
        })
    
    return Response({
        'versions': data,
        'count': len(data)
    }, status=status.HTTP_200_OK)


def _get_store_url_for_response(platform, version):
    """Helper to get store URL"""
    if platform == 'ios':
        return version.ios_store_url
    elif platform == 'android':
        return version.android_store_url
    return None


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def first_login_announcement_view(request):
    """Return a first-time login announcement.

    Priority:
    1) Announcement row in DB (kind=first_login, tenant='ontime', is_active and within schedule)
    2) Fallback to settings FIRST_LOGIN_TITLE/BODY
    3) 404 if none
    """
    # For now, scope to fixed tenant 'ontime' as requested
    q = Announcement.objects.filter(kind=Announcement.KIND_FIRST_LOGIN, tenant='ontime', is_active=True)
    # Filter by schedule window
    now = timezone.now()
    q = q.filter(models.Q(starts_at__isnull=True) | models.Q(starts_at__lte=now))
    q = q.filter(models.Q(ends_at__isnull=True) | models.Q(ends_at__gte=now))
    ann = q.order_by('-updated_at').first()
    if ann and (ann.title.strip() or ann.body.strip()):
        return Response({'title': ann.title.strip(), 'body': ann.body.strip()}, status=status.HTTP_200_OK)

    # Fallback to settings
    title = (getattr(settings, 'FIRST_LOGIN_TITLE', '') or '').strip()
    body = (getattr(settings, 'FIRST_LOGIN_BODY', '') or '').strip()
    if title or body:
        return Response({'title': title, 'body': body}, status=status.HTTP_200_OK)
    return Response({'detail': 'No announcement'}, status=status.HTTP_404_NOT_FOUND)
