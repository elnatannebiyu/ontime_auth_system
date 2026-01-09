"""
AUDIT FIX #4: IP Allowlisting Middleware for Django Admin Interface

This middleware restricts access to the Django admin interface to specific IP addresses.
Configure allowed IPs via ADMIN_ALLOWED_IPS environment variable (comma-separated).
"""
import os
from django.http import HttpResponseForbidden
from django.conf import settings


def get_client_ip(request):
    """Extract client IP from request, considering X-Forwarded-For."""
    x_forwarded_for = request.META.get('HTTP_X_FORWARDED_FOR')
    if x_forwarded_for:
        ip = x_forwarded_for.split(',')[0].strip()
    else:
        ip = request.META.get('REMOTE_ADDR', '')
    return ip


class AdminIPAllowlistMiddleware:
    """Restrict Django admin access to allowlisted IPs only."""
    
    def __init__(self, get_response):
        self.get_response = get_response
        # Load allowed IPs from environment variable
        allowed_ips_str = os.environ.get('ADMIN_ALLOWED_IPS', '')
        self.allowed_ips = set()
        if allowed_ips_str:
            self.allowed_ips = {ip.strip() for ip in allowed_ips_str.split(',') if ip.strip()}
        
        # Get admin URL path
        self.admin_path = os.environ.get('ADMIN_URL_PATH', 'secret-admin-panel')
        
        # In DEBUG mode, allow localhost by default
        if settings.DEBUG:
            self.allowed_ips.update(['127.0.0.1', '::1', 'localhost'])
    
    def __call__(self, request):
        # Check if this is an admin request
        path = request.path.lstrip('/')
        if path.startswith(f'{self.admin_path}/'):
            # If no IPs configured and not DEBUG, block all (fail-secure)
            if not self.allowed_ips and not settings.DEBUG:
                return HttpResponseForbidden(
                    '<h1>Access Denied</h1>'
                    '<p>Admin interface access is restricted. Configure ADMIN_ALLOWED_IPS.</p>'
                )
            
            # Check client IP
            client_ip = get_client_ip(request)
            if client_ip not in self.allowed_ips:
                return HttpResponseForbidden(
                    f'<h1>Access Denied</h1>'
                    f'<p>Your IP address ({client_ip}) is not authorized to access this interface.</p>'
                )
        
        response = self.get_response(request)
        return response
