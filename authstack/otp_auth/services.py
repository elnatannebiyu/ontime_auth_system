from django.conf import settings
from django.core.mail import send_mail
from django.template.loader import render_to_string
import logging

logger = logging.getLogger(__name__)

class OTPService:
    """Service for sending OTP via email/SMS"""
    
    @staticmethod
    def send_email_otp(email, otp_code, purpose='login'):
        """Send OTP via email"""
        try:
            subject_map = {
                'login': 'Your Login Code',
                'register': 'Verify Your Email',
                'verify': 'Email Verification Code',
                'reset': 'Password Reset Code',
            }
            
            subject = subject_map.get(purpose, 'Your Verification Code')
            
            # Simple text message
            message = f"""Your verification code is: {otp_code}
            
This code will expire in 10 minutes.

If you didn't request this code, please ignore this email.
"""
            
            # HTML message (optional)
            html_message = f"""
            <div style="font-family: Arial, sans-serif; max-width: 600px; margin: 0 auto;">
                <h2>Your Verification Code</h2>
                <div style="background: #f5f5f5; padding: 20px; border-radius: 5px; margin: 20px 0;">
                    <h1 style="text-align: center; color: #333; letter-spacing: 5px;">{otp_code}</h1>
                </div>
                <p>This code will expire in 10 minutes.</p>
                <p style="color: #666; font-size: 14px;">If you didn't request this code, please ignore this email.</p>
            </div>
            """
            
            send_mail(
                subject,
                message,
                settings.DEFAULT_FROM_EMAIL,
                [email],
                html_message=html_message,
                fail_silently=False,
            )
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to send email OTP: {e}")
            return False
    
    @staticmethod
    def send_sms_otp(phone, otp_code, purpose='login'):
        """Send OTP via SMS using Twilio"""
        try:
            # For development, just log it
            if settings.DEBUG:
                logger.info(f"SMS OTP for {phone}: {otp_code}")
                return True
            
            # Production: Use Twilio
            # from twilio.rest import Client
            # 
            # client = Client(settings.TWILIO_ACCOUNT_SID, settings.TWILIO_AUTH_TOKEN)
            # 
            # message = client.messages.create(
            #     body=f"Your verification code is: {otp_code}",
            #     from_=settings.TWILIO_PHONE_NUMBER,
            #     to=phone
            # )
            # 
            # return message.sid is not None
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to send SMS OTP: {e}")
            return False
