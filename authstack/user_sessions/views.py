import logging
from rest_framework.views import APIView
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response
from rest_framework import status
from django.utils import timezone
from django.db import transaction
from .models import Device

logger = logging.getLogger(__name__)


class RegisterDeviceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        data = request.data or {}
        device_id = (data.get('device_id') or '').strip()
        device_type = (data.get('device_type') or '').strip().lower()  # ios | android | web
        push_token = (data.get('push_token') or '').strip()
        app_version = (data.get('app_version') or '').strip()
        device_name = (data.get('device_name') or '').strip()
        device_model = (data.get('device_model') or '').strip()

        if not device_id or not device_type:
            logger.info('[RegisterDevice] user=%s missing device_id/device_type device_id=%r device_type=%r', user.id, device_id, device_type)
            return Response({'error': 'device_id and device_type are required'}, status=status.HTTP_400_BAD_REQUEST)

        # Use a transaction so reassignment + updates are atomic
        with transaction.atomic():
            created = False
            # If another row already owns this device_id (due to unique constraint), reassign it
            try:
                existing = Device.objects.select_for_update().get(device_id=device_id)
                device = existing
                if device.user_id != user.id:
                    logger.info('[RegisterDevice] Reassigning device_id=%s from user=%s to user=%s', device_id, device.user_id, user.id)
                    device.user = user
                # Update fields
                if device.device_type != device_type:
                    device.device_type = device_type
                if device_name:
                    device.device_name = device_name
                if device_model:
                    device.device_model = device_model
                if push_token:
                    device.push_token = push_token
                    device.push_enabled = True
                device.last_seen_at = timezone.now()
                device.save()
            except Device.DoesNotExist:
                # Safe to create new
                device = Device(
                    user=user,
                    device_id=device_id,
                    device_type=device_type,
                    device_name=device_name or device_type,
                    device_model=device_model,
                )
                if push_token:
                    device.push_token = push_token
                    device.push_enabled = True
                device.last_seen_at = timezone.now()
                device.save()
                created = True

            # Resolve push_token conflicts: disable other users with same token
            if push_token:
                (Device.objects
                 .filter(push_token=push_token)
                 .exclude(pk=device.pk)
                 .update(push_enabled=False, last_seen_at=timezone.now()))

        logger.info('[RegisterDevice] user=%s device_id=%s created=%s push_token_present=%s push_enabled=%s',
                    user.id, device_id, created, bool(push_token), device.push_enabled)

        # STRICT MODE: ensure this physical device/token is not active for any other user
        # Disable by device_id for other users
        disabled_by_id = 0
        if device_id:
            disabled_by_id = (Device.objects
                              .filter(device_id=device_id)
                              .exclude(user=user)
                              .update(push_enabled=False, last_seen_at=timezone.now()))
        # Disable by push_token for other users (covers reinstall/new device_id cases)
        disabled_by_token = 0
        if push_token:
            disabled_by_token = (Device.objects
                                 .filter(push_token=push_token)
                                 .exclude(user=user)
                                 .update(push_enabled=False, last_seen_at=timezone.now()))

        logger.info('[RegisterDevice] strict-disabled others: by_device_id=%s by_token=%s', disabled_by_id, disabled_by_token)

        return Response({
            'id': str(device.id),
            'device_id': device.device_id,
            'device_type': device.device_type,
            'push_enabled': device.push_enabled,
        }, status=status.HTTP_200_OK)


class UnregisterDeviceView(APIView):
    permission_classes = [IsAuthenticated]

    def post(self, request):
        user = request.user
        data = request.data or {}
        # Prefer header-provided device id
        device_id = (request.headers.get('X-Device-Id') or data.get('device_id') or '').strip()
        push_token = (data.get('push_token') or '').strip()

        qs = Device.objects.filter(user=user, push_enabled=True)
        if device_id:
            qs = qs.filter(device_id=device_id)
        elif push_token:
            qs = qs.filter(push_token=push_token)
        # if neither provided, we conservatively disable none (no-op)
        updated = 0
        if device_id or push_token:
            updated = qs.update(push_enabled=False, last_seen_at=timezone.now())
        logger.info('[UnregisterDevice] user=%s device_id=%r push_token_present=%s disabled=%s', user.id, device_id, bool(push_token), updated)
        return Response({'disabled': updated}, status=status.HTTP_200_OK)
