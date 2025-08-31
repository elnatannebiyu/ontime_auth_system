import random
import string
import uuid
from datetime import timedelta
from django.db import models
from django.contrib.auth import get_user_model
from django.utils import timezone
from django.core.validators import RegexValidator
from django.conf import settings
import hashlib

User = get_user_model()

class OTPRequest(models.Model):
    """Track OTP requests for rate limiting and verification"""
    
    OTP_TYPE_CHOICES = [
        ('email', 'Email'),
        ('phone', 'Phone'),
    ]
    
    PURPOSE_CHOICES = [
        ('login', 'Login'),
        ('register', 'Registration'),
        ('verify', 'Verification'),
        ('reset', 'Password Reset'),
    ]
    
    id = models.UUIDField(primary_key=True, default=uuid.uuid4)
    user = models.ForeignKey(User, on_delete=models.CASCADE, null=True, blank=True)
    
    # Contact details
    otp_type = models.CharField(max_length=10, choices=OTP_TYPE_CHOICES)
    destination = models.CharField(max_length=255, db_index=True)  # email or phone
    
    # OTP details
    otp_code = models.CharField(max_length=6)
    otp_hash = models.CharField(max_length=128)  # For extra security
    purpose = models.CharField(max_length=20, choices=PURPOSE_CHOICES)
    
    # Status
    is_verified = models.BooleanField(default=False)
    attempts = models.IntegerField(default=0)
    max_attempts = models.IntegerField(default=3)
    
    # Timestamps
    created_at = models.DateTimeField(auto_now_add=True)
    expires_at = models.DateTimeField()
    verified_at = models.DateTimeField(null=True, blank=True)
    
    # Metadata
    ip_address = models.GenericIPAddressField(null=True, blank=True)
    user_agent = models.CharField(max_length=255, blank=True)
    
    class Meta:
        db_table = 'otp_requests'
        indexes = [
            models.Index(fields=['destination', '-created_at']),
            models.Index(fields=['otp_code', 'destination']),
        ]
    
    @classmethod
    def create_otp(cls, otp_type, destination, purpose, user=None, request=None):
        """Create new OTP request"""
        # Generate 6-digit OTP
        otp_code = ''.join(random.choices(string.digits, k=6))
        
        # For development and testing, use simple codes
        import sys
        if settings.DEBUG or 'test' in sys.argv:
            otp_code = '123456'
        
        # Hash for storage
        otp_hash = hashlib.sha256(f"{otp_code}{destination}".encode()).hexdigest()
        
        # Set expiry (5 minutes for phone, 10 for email)
        if otp_type == 'phone':
            expires_at = timezone.now() + timedelta(minutes=5)
        else:
            expires_at = timezone.now() + timedelta(minutes=10)
        
        # Get request metadata
        ip_address = '0.0.0.0'
        user_agent = ''
        if request:
            x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
            if x_forwarded_for:
                ip_address = x_forwarded_for.split(',')[0]
            else:
                ip_address = request.META.get('REMOTE_ADDR', '0.0.0.0')
            user_agent = request.META.get('HTTP_USER_AGENT', '')
        
        otp_request = cls.objects.create(
            user=user,
            otp_type=otp_type,
            destination=destination,
            otp_code=otp_code,
            otp_hash=otp_hash,
            purpose=purpose,
            expires_at=expires_at,
            ip_address=ip_address,
            user_agent=user_agent
        )
        
        return otp_request
    
    def verify(self, code):
        """Verify OTP code"""
        if self.is_verified:
            return False, 'OTP already used'
        
        if self.expires_at < timezone.now():
            return False, 'OTP expired'
        
        if self.attempts >= self.max_attempts:
            return False, 'Too many attempts'
        
        self.attempts += 1
        self.save()
        
        # Compare hashed OTP
        code_hash = hashlib.sha256(f"{code}{self.destination}".encode()).hexdigest()
        if self.otp_hash != code_hash:
            return False, 'Invalid OTP'
        
        # Mark as verified
        self.is_verified = True
        self.verified_at = timezone.now()
        self.save()
        
        return True, 'OTP verified'
    
    @classmethod
    def check_rate_limit(cls, destination, limit_minutes=60, max_requests=5):
        """Check if destination has exceeded rate limit"""
        since = timezone.now() - timedelta(minutes=limit_minutes)
        count = cls.objects.filter(
            destination=destination,
            created_at__gte=since
        ).count()
        
        return count >= max_requests
