"""
Custom validators for enhanced security
"""
import re
from django.core.exceptions import ValidationError
from django.conf import settings
from django.utils.translation import gettext as _


class CustomPasswordValidator:
    """
    Validate that the password meets security requirements:
    - At least 8 characters
    - Contains uppercase and lowercase letters
    - Contains at least one digit
    - Contains at least one special character
    """
    
    def validate(self, password, user=None):
        if len(password) < 8:
            raise ValidationError(
                _("Password must be at least 8 characters long."),
                code='password_too_short',
            )
        
        if not re.search(r'[A-Z]', password):
            raise ValidationError(
                _("Password must contain at least one uppercase letter."),
                code='password_no_upper',
            )
        
        if not re.search(r'[a-z]', password):
            raise ValidationError(
                _("Password must contain at least one lowercase letter."),
                code='password_no_lower',
            )
        
        if not re.search(r'\d', password):
            raise ValidationError(
                _("Password must contain at least one digit."),
                code='password_no_digit',
            )
        
        if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
            raise ValidationError(
                _("Password must contain at least one special character (!@#$%^&*(),.?\":{}|<>)."),
                code='password_no_special',
            )
    
    def get_help_text(self):
        return _(
            "Your password must contain at least 8 characters, including uppercase "
            "and lowercase letters, numbers, and special characters."
        )


def validate_email_domain(email):
    """
    Validate email domain is allowed and not from temporary email services
    """
    blocked_domains = [
        'tempmail.com', 'throwaway.email', '10minutemail.com',
        'guerrillamail.com', 'mailinator.com', 'temp-mail.org'
    ]
    
    domain = email.split('@')[-1].lower()
    if domain in blocked_domains:
        raise ValidationError(
            _("Registration with temporary email addresses is not allowed."),
            code='temporary_email',
        )
    # If allowlist configured, enforce it
    allowed = getattr(settings, 'EMAIL_ALLOWED_DOMAINS', []) or []
    if allowed:
        if domain not in {d.lower() for d in allowed}:
            raise ValidationError(
                _("Only emails from allowed domains are accepted."),
                code='email_domain_not_allowed',
            )


def sanitize_input(text):
    """
    Basic input sanitization to prevent XSS
    """
    if not text:
        return text
    
    # Remove potentially dangerous HTML tags and scripts
    import html
    text = html.escape(text)
    
    # Additional sanitization can be added here
    return text
