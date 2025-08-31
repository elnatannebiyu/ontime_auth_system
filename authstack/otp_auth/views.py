from django.utils import timezone
from django.contrib.auth import get_user_model
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response
from django.core.validators import validate_email
from django.core.exceptions import ValidationError
from datetime import timedelta
import re
import uuid
from django.conf import settings
from .models import OTPRequest
from .services import OTPService

User = get_user_model()

@api_view(['POST'])
@permission_classes([AllowAny])
def request_otp_view(request):
    """Request OTP for login/registration"""
    destination = request.data.get('destination', '').strip()
    purpose = request.data.get('purpose', 'login')
    
    if not destination:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Email or phone number required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Determine type (email or phone)
    otp_type = None
    
    # Check if email
    try:
        validate_email(destination)
        otp_type = 'email'
    except ValidationError:
        # Check if phone (E.164 format)
        if re.match(r'^\+[1-9]\d{1,14}$', destination):
            otp_type = 'phone'
    
    if not otp_type:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'Invalid email or phone number'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Check rate limiting
    if OTPRequest.check_rate_limit(destination):
        return Response({
            'code': 'RATE_LIMIT',
            'message': 'Too many OTP requests. Please try again later.'
        }, status=status.HTTP_429_TOO_MANY_REQUESTS)
    
    # Check if user exists (for login)
    user = None
    if purpose == 'login':
        if otp_type == 'email':
            user = User.objects.filter(email=destination).first()
        else:
            # Check for phone_e164 field if it exists
            if hasattr(User, 'phone_e164'):
                user = User.objects.filter(phone_e164=destination).first()
        
        if not user:
            return Response({
                'code': 'USER_NOT_FOUND',
                'message': 'No account found with this email/phone'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Check user status if field exists
        if hasattr(user, 'status') and user.status != 'active':
            return Response({
                'code': 'ACCOUNT_DISABLED',
                'message': 'Account is not active'
            }, status=status.HTTP_403_FORBIDDEN)
    
    # Create OTP request
    otp_request = OTPRequest.create_otp(
        otp_type=otp_type,
        destination=destination,
        purpose=purpose,
        user=user,
        request=request
    )
    
    # Send OTP
    if otp_type == 'email':
        success = OTPService.send_email_otp(destination, otp_request.otp_code, purpose)
    else:
        success = OTPService.send_sms_otp(destination, otp_request.otp_code, purpose)
    
    if not success:
        otp_request.delete()
        return Response({
            'code': 'SEND_FAILED',
            'message': f'Failed to send OTP to {otp_type}'
        }, status=status.HTTP_500_INTERNAL_SERVER_ERROR)
    
    return Response({
        'message': f'OTP sent to {otp_type}',
        'otp_id': str(otp_request.id),
        'expires_in': 300 if otp_type == 'phone' else 600,  # seconds
        'destination_masked': _mask_destination(destination, otp_type)
    }, status=status.HTTP_200_OK)

@api_view(['POST'])
@permission_classes([AllowAny])
def verify_otp_view(request):
    """Verify OTP and login"""
    otp_id = request.data.get('otp_id')
    otp_code = request.data.get('otp_code', '').strip()
    
    if not otp_id or not otp_code:
        return Response({
            'code': 'VALIDATION_ERROR',
            'message': 'OTP ID and code required'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    try:
        otp_request = OTPRequest.objects.get(id=otp_id)
    except OTPRequest.DoesNotExist:
        return Response({
            'code': 'INVALID_OTP',
            'message': 'Invalid OTP request'
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Verify OTP
    success, message = otp_request.verify(otp_code)
    
    if not success:
        return Response({
            'code': 'INVALID_OTP',
            'message': message
        }, status=status.HTTP_400_BAD_REQUEST)
    
    # Handle based on purpose
    if otp_request.purpose == 'login':
        # Login user
        user = otp_request.user
        if not user:
            # Find user by destination
            if otp_request.otp_type == 'email':
                user = User.objects.filter(email=otp_request.destination).first()
            else:
                if hasattr(User, 'phone_e164'):
                    user = User.objects.filter(phone_e164=otp_request.destination).first()
        
        if not user:
            return Response({
                'code': 'USER_NOT_FOUND',
                'message': 'User not found'
            }, status=status.HTTP_404_NOT_FOUND)
        
        # Create session
        from user_sessions.models import Session, Device
        from accounts.jwt_auth import CustomTokenObtainPairSerializer
        
        # Get device info
        device = None
        device_id = request.data.get('device_id')
        if device_id:
            device, _ = Device.objects.update_or_create(
                device_id=device_id,
                user=user,
                defaults={
                    'device_type': request.data.get('device_type', 'web'),
                    'device_name': request.data.get('device_name', 'Unknown Device'),
                    'last_seen_at': timezone.now(),
                }
            )
        
        # Create JWT tokens
        refresh = CustomTokenObtainPairSerializer.get_token(user)
        refresh['tenant_id'] = request.META.get('HTTP_X_TENANT_ID', 'default')
        access = refresh.access_token
        
        # Get IP address and user agent
        x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
        if x_forwarded_for:
            ip_address = x_forwarded_for.split(',')[0]
        else:
            ip_address = request.META.get('REMOTE_ADDR', '0.0.0.0')
        user_agent = request.META.get('HTTP_USER_AGENT', '')
        
        # Create session with proper fields
        import secrets
        import hashlib
        refresh_token = secrets.token_urlsafe(32)
        refresh_token_hash = hashlib.sha256(refresh_token.encode()).hexdigest()
        
        session = Session.objects.create(
            user=user,
            device=device,
            ip_address=ip_address,
            user_agent=user_agent,
            refresh_token_hash=refresh_token_hash,
            refresh_token_family=str(uuid.uuid4()),
            rotation_counter=0,
            expires_at=timezone.now() + timedelta(days=7)
        )
        
        # Add session info to tokens
        refresh['sid'] = str(session.id)
        access['sid'] = str(session.id)
        
        # Mark phone/email as verified if fields exist
        if otp_request.otp_type == 'email' and hasattr(user, 'email_verified'):
            user.email_verified = True
            user.save()
        elif otp_request.otp_type == 'phone' and hasattr(user, 'phone_verified'):
            user.phone_verified = True
            user.save()
        
        # Set refresh token in HTTP-only cookie
        response = Response({
            'access': str(access),
            'session_id': str(session.id),
            'expires_in': settings.SIMPLE_JWT['ACCESS_TOKEN_LIFETIME'].total_seconds(),
            'user': {
                'id': str(user.id),
                'username': user.username,
                'email': user.email,
            }
        }, status=status.HTTP_200_OK)
        
        # Set refresh token cookie
        response.set_cookie(
            key='refresh_token',
            value=str(refresh),
            max_age=settings.SIMPLE_JWT['REFRESH_TOKEN_LIFETIME'].total_seconds(),
            httponly=True,
            samesite='Lax',
            secure=not settings.DEBUG
        )
        
        return response
    
    elif otp_request.purpose == 'register':
        # For registration, return success and let registration endpoint handle it
        return Response({
            'message': 'OTP verified',
            'verified_destination': otp_request.destination,
            'verification_token': str(otp_request.id)  # Use this in registration
        }, status=status.HTTP_200_OK)
    
    else:
        # For verification/reset, just return success
        return Response({
            'message': 'OTP verified successfully'
        }, status=status.HTTP_200_OK)

def _mask_destination(destination, otp_type):
    """Mask email or phone for privacy"""
    if otp_type == 'email':
        parts = destination.split('@')
        if len(parts) == 2:
            name = parts[0]
            if len(name) > 2:
                masked = name[0] + '*' * (len(name) - 2) + name[-1]
            else:
                masked = name[0] + '*'
            return f"{masked}@{parts[1]}"
    else:
        # Phone
        if len(destination) > 6:
            return destination[:3] + '*' * (len(destination) - 6) + destination[-3:]
    
    return destination
