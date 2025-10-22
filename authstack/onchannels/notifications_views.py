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
      - page (default 1)
      - page_size (default 20, max 100)
      - read: '0' for unread only, '1' for read only, omit for all
    """
    user = request.user
    qs = UserNotification.objects.filter(user=user)
    read = request.GET.get('read')
    if read == '0':
        qs = qs.filter(read_at__isnull=True)
    elif read == '1':
        qs = qs.filter(read_at__isnull=False)

    try:
        page_num = int(request.GET.get('page', 1))
    except Exception:
        page_num = 1
    try:
        page_size = int(request.GET.get('page_size', 20))
    except Exception:
        page_size = 20
    page_size = max(1, min(page_size, 100))

    paginator = Paginator(qs.order_by('-created_at'), page_size)
    page = paginator.get_page(page_num)
    items = [
        {
            'id': n.id,
            'title': n.title,
            'body': n.body,
            'data': n.data or {},
            'created_at': n.created_at.isoformat(),
            'read_at': n.read_at.isoformat() if n.read_at else None,
        }
        for n in page.object_list
    ]
    return Response({
        'count': paginator.count,
        'page': page.number,
        'pages': paginator.num_pages,
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
