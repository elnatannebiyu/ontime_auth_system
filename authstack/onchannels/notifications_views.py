from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from django.core.paginator import Paginator
from django.utils import timezone
from .models import UserNotification


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def list_notifications_view(request):
    """Return paginated notifications for the current user.

    Query params:
      - read: '0' for unread only, '1' for read only, omit for all
      
    NOTE: This endpoint previously paginated with a default page_size=20. It
    now returns all matching notifications in a single response, ordered by
    newest first. The response shape still includes count/page/pages/results
    for backward compatibility, but page/pages are always 1.
    """
    user = request.user
    qs = UserNotification.objects.filter(user=user)
    read = request.GET.get('read')
    if read == '0':
        qs = qs.filter(read_at__isnull=True)
    elif read == '1':
        qs = qs.filter(read_at__isnull=False)

    qs = qs.order_by('-created_at')
    items = [
        {
            'id': n.id,
            'title': n.title,
            'body': n.body,
            'data': n.data or {},
            'created_at': n.created_at.isoformat(),
            'read_at': n.read_at.isoformat() if n.read_at else None,
        }
        for n in qs
    ]
    return Response({
        'count': len(items),
        'page': 1,
        'pages': 1,
        'results': items,
    })


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def mark_read_view(request):
    """Mark specific notifications as read for the current user.

    Body: {"ids": [1,2,3]}
    """
    user = request.user
    ids = request.data.get('ids') or []
    if not isinstance(ids, list) or not ids:
        return Response({'detail': 'ids must be a non-empty list'}, status=status.HTTP_400_BAD_REQUEST)
    now = timezone.now()
    updated = UserNotification.objects.filter(user=user, id__in=ids, read_at__isnull=True).update(read_at=now)
    return Response({'updated': updated})


@api_view(['POST'])
@permission_classes([IsAuthenticated])
def mark_all_read_view(request):
    """Mark all unread notifications as read for the current user."""
    user = request.user
    now = timezone.now()
    updated = UserNotification.objects.filter(user=user, read_at__isnull=True).update(read_at=now)
    return Response({'updated': updated})


@api_view(['DELETE'])
@permission_classes([IsAuthenticated])
def delete_notification_view(request, pk: int):
    """Delete a single notification for the current user."""
    user = request.user
    try:
        n = UserNotification.objects.get(id=pk, user=user)
    except UserNotification.DoesNotExist:
        return Response({'detail': 'Not found.'}, status=status.HTTP_404_NOT_FOUND)
    n.delete()
    return Response(status=status.HTTP_204_NO_CONTENT)


@api_view(['GET'])
@permission_classes([IsAuthenticated])
def unread_count_view(request):
    """Return the unread notifications count for the current user."""
    user = request.user
    count = UserNotification.objects.filter(user=user, read_at__isnull=True).count()
    return Response({'count': count})
