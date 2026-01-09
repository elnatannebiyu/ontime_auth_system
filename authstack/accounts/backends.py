"""
Custom authentication backend that allows login with email or username.
"""
from django.contrib.auth.backends import ModelBackend
from django.contrib.auth import get_user_model

User = get_user_model()


class EmailOrUsernameBackend(ModelBackend):
    """
    Authenticate using either username or email address.
    
    This allows users to login with their email (e.g., user@example.com)
    or their username (e.g., johndoe).
    """
    
    def authenticate(self, request, username=None, password=None, **kwargs):
        if username is None or password is None:
            return None
        
        # Try to find user by username first (case-insensitive)
        user = User.objects.filter(username__iexact=username).first()
        
        # If not found, try by email (case-insensitive)
        if user is None:
            user = User.objects.filter(email__iexact=username).first()
        
        # If user found, check password
        if user and user.check_password(password):
            return user
        
        return None
