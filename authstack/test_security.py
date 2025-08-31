#!/usr/bin/env python
"""
Test script to verify security features are working
Run with: python test_security.py
"""
import os
import sys
import django
import time

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'authstack.settings')
django.setup()

from django.test import Client
from django.contrib.auth.models import User
from accounts.validators import CustomPasswordValidator, validate_email_domain
from django.core.exceptions import ValidationError

def test_password_validation():
    """Test password strength requirements"""
    print("\n=== Testing Password Validation ===")
    
    validator = CustomPasswordValidator()
    
    # Test weak passwords
    weak_passwords = [
        ("short", "Password too short"),
        ("alllowercase123!", "No uppercase"),
        ("ALLUPPERCASE123!", "No lowercase"),
        ("NoNumbers!", "No digit"),
        ("NoSpecialChar123", "No special character"),
    ]
    
    for password, reason in weak_passwords:
        try:
            validator.validate(password)
            print(f"❌ FAILED: '{password}' should be rejected ({reason})")
        except ValidationError as e:
            print(f"✅ PASSED: '{password}' rejected - {e.messages[0]}")
    
    # Test strong password
    strong_password = "StrongP@ssw0rd123"
    try:
        validator.validate(strong_password)
        print(f"✅ PASSED: '{strong_password}' accepted as strong password")
    except ValidationError as e:
        print(f"❌ FAILED: Strong password rejected - {e.messages}")

def test_email_validation():
    """Test email domain blocking"""
    print("\n=== Testing Email Validation ===")
    
    # Test blocked domains
    blocked_emails = [
        "test@tempmail.com",
        "user@10minutemail.com",
        "fake@mailinator.com"
    ]
    
    for email in blocked_emails:
        try:
            validate_email_domain(email)
            print(f"❌ FAILED: '{email}' should be blocked")
        except ValidationError:
            print(f"✅ PASSED: '{email}' blocked (temporary email)")
    
    # Test valid domain
    valid_email = "user@gmail.com"
    try:
        validate_email_domain(valid_email)
        print(f"✅ PASSED: '{valid_email}' accepted")
    except ValidationError:
        print(f"❌ FAILED: Valid email rejected")

def test_rate_limiting():
    """Test rate limiting on login endpoint"""
    print("\n=== Testing Rate Limiting ===")
    
    client = Client()
    
    # Test login rate limit (5 attempts per minute)
    print("Testing login rate limit (5/minute)...")
    
    for i in range(7):
        response = client.post('/api/token/', {
            'username': 'test@example.com',
            'password': 'wrongpassword',
            'tenant_id': 'ontime'
        }, HTTP_X_TENANT_ID='ontime')
        
        if i < 5:
            if response.status_code in [400, 401]:
                print(f"  Attempt {i+1}: ✅ Login failed (expected)")
            else:
                print(f"  Attempt {i+1}: Status {response.status_code}")
        else:
            if response.status_code == 429:
                print(f"  Attempt {i+1}: ✅ Rate limited (429)")
            else:
                print(f"  Attempt {i+1}: ❌ Not rate limited (got {response.status_code})")

def test_registration_rate_limit():
    """Test rate limiting on registration endpoint"""
    print("\n=== Testing Registration Rate Limit ===")
    
    client = Client()
    
    # Test registration rate limit (3 per hour)
    print("Testing registration rate limit (3/hour)...")
    
    for i in range(5):
        response = client.post('/api/register/', {
            'email': f'test{i}@example.com',
            'password': 'TestP@ssw0rd123'
        }, HTTP_X_TENANT_ID='ontime')
        
        if i < 3:
            print(f"  Attempt {i+1}: Status {response.status_code}")
        else:
            if response.status_code == 429:
                print(f"  Attempt {i+1}: ✅ Rate limited (429)")
            else:
                print(f"  Attempt {i+1}: ❌ Not rate limited (got {response.status_code})")

def test_brute_force_protection():
    """Test brute force protection with django-axes"""
    print("\n=== Testing Brute Force Protection ===")
    
    client = Client()
    
    # Create a test user
    test_user = User.objects.filter(username='brutetest@example.com').first()
    if not test_user:
        test_user = User.objects.create_user(
            username='brutetest@example.com',
            email='brutetest@example.com',
            password='TestP@ssw0rd123'
        )
        print("Created test user: brutetest@example.com")
    
    # Test failed login attempts (axes should lock after 5)
    print("Testing account lockout after 5 failed attempts...")
    
    for i in range(7):
        response = client.post('/api/token/', {
            'username': 'brutetest@example.com',
            'password': 'wrongpassword',
        }, HTTP_X_TENANT_ID='ontime')
        
        if i < 5:
            print(f"  Attempt {i+1}: Status {response.status_code} (failed login)")
        else:
            if response.status_code == 403:
                print(f"  Attempt {i+1}: ✅ Account locked (403)")
            else:
                print(f"  Attempt {i+1}: Status {response.status_code}")

def main():
    print("=" * 50)
    print("SECURITY FEATURES TEST SUITE")
    print("=" * 50)
    
    test_password_validation()
    test_email_validation()
    test_rate_limiting()
    test_registration_rate_limit()
    test_brute_force_protection()
    
    print("\n" + "=" * 50)
    print("TEST SUITE COMPLETE")
    print("=" * 50)

if __name__ == "__main__":
    main()
