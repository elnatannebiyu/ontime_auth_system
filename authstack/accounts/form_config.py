from django.conf import settings
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import AllowAny
from rest_framework.response import Response


class FormConfiguration:
    """Centralized form configuration"""
    
    # Field constraints
    USERNAME_MIN_LENGTH = 3
    USERNAME_MAX_LENGTH = 20
    PASSWORD_MIN_LENGTH = 8
    
    # Feature flags
    REQUIRE_EMAIL_VERIFICATION = True
    REQUIRE_PHONE_VERIFICATION = False
    ALLOW_USERNAME_LOGIN = True
    ALLOW_EMAIL_LOGIN = True
    ALLOW_PHONE_LOGIN = False
    
    # Social auth
    SOCIAL_AUTH_PROVIDERS = ['google', 'apple', 'facebook']
    
    # OTP settings
    OTP_LENGTH = 6
    OTP_EXPIRY_MINUTES = 10
    OTP_RESEND_COOLDOWN = 60
    
    # Password policy
    PASSWORD_REQUIRE_UPPERCASE = True
    PASSWORD_REQUIRE_LOWERCASE = True
    PASSWORD_REQUIRE_DIGIT = True
    PASSWORD_REQUIRE_SPECIAL = True
    
    @classmethod
    def get_config(cls):
        """Get form configuration as dict"""
        return {
            'username': {
                'min_length': cls.USERNAME_MIN_LENGTH,
                'max_length': cls.USERNAME_MAX_LENGTH,
                'pattern': '^[a-zA-Z0-9_]+$'
            },
            'password': {
                'min_length': cls.PASSWORD_MIN_LENGTH,
                'require_uppercase': cls.PASSWORD_REQUIRE_UPPERCASE,
                'require_lowercase': cls.PASSWORD_REQUIRE_LOWERCASE,
                'require_digit': cls.PASSWORD_REQUIRE_DIGIT,
                'require_special': cls.PASSWORD_REQUIRE_SPECIAL
            },
            'features': {
                'email_verification': cls.REQUIRE_EMAIL_VERIFICATION,
                'phone_verification': cls.REQUIRE_PHONE_VERIFICATION,
                'username_login': cls.ALLOW_USERNAME_LOGIN,
                'email_login': cls.ALLOW_EMAIL_LOGIN,
                'phone_login': cls.ALLOW_PHONE_LOGIN,
                'social_auth': cls.SOCIAL_AUTH_PROVIDERS
            },
            'otp': {
                'length': cls.OTP_LENGTH,
                'expiry': cls.OTP_EXPIRY_MINUTES,
                'resend_cooldown': cls.OTP_RESEND_COOLDOWN
            }
        }


@api_view(['GET'])
@permission_classes([AllowAny])
def get_form_config_view(request):
    """Get form configuration for client"""
    config = FormConfiguration.get_config()
    return Response(config, status=status.HTTP_200_OK)
