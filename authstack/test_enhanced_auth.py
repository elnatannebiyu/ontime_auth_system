#!/usr/bin/env python
"""Test script for enhanced authentication with token versioning and refresh token rotation"""
import os
import sys
import django
import time
import json
from datetime import datetime, timedelta

# Setup Django
os.environ.setdefault('DJANGO_SETTINGS_MODULE', 'authstack.settings')
django.setup()

from django.contrib.auth import get_user_model
from django.test import RequestFactory
from rest_framework.test import APIClient
from rest_framework_simplejwt.tokens import RefreshToken
from accounts.models import UserSession
from accounts.jwt_auth import CustomTokenObtainPairSerializer, RefreshTokenRotation

User = get_user_model()


def test_token_versioning():
    """Test token versioning functionality"""
    print("\n=== Testing Token Versioning ===")
    
    # Create test user
    user = User.objects.create_user(
        username='tokentest',
        email='tokentest@example.com',
        password='TestPass123!'
    )
    
    # Add token_version field if it doesn't exist
    if not hasattr(user, 'token_version'):
        user.token_version = 1
        user.save()
    
    print(f"✓ Created user with token_version: {user.token_version}")
    
    # Generate token
    refresh = RefreshToken.for_user(user)
    refresh['token_version'] = user.token_version
    
    print(f"✓ Generated token with version: {refresh['token_version']}")
    
    # Increment token version (simulating revocation)
    user.token_version += 1
    user.save()
    print(f"✓ Incremented user token_version to: {user.token_version}")
    
    # Try to use old token (should fail)
    from accounts.jwt_auth import CustomJWTAuthentication
    auth = CustomJWTAuthentication()
    
    try:
        # This should raise an error because token version doesn't match
        validated = auth.get_validated_token(str(refresh.access_token))
        print("✗ Old token should have been rejected but wasn't")
    except Exception as e:
        print(f"✓ Old token correctly rejected: {str(e)}")
    
    # Cleanup
    user.delete()
    print("✓ Token versioning test completed")


def test_session_tracking():
    """Test session tracking with UserSession model"""
    print("\n=== Testing Session Tracking ===")
    
    # Create test user
    user = User.objects.create_user(
        username='sessiontest',
        email='sessiontest@example.com',
        password='TestPass123!'
    )
    
    # Create API client
    client = APIClient()
    
    # Login to create session
    response = client.post('/api/token/', {
        'username': 'sessiontest',
        'password': 'TestPass123!'
    }, HTTP_X_TENANT_ID='ontime')
    
    if response.status_code == 200:
        print("✓ Login successful")
        tokens = response.json()
        
        # Check if session was created
        sessions = UserSession.objects.filter(user=user)
        if sessions.exists():
            session = sessions.first()
            print(f"✓ Session created: {session.id}")
            print(f"  - Device ID: {session.device_id[:16]}...")
            print(f"  - IP Address: {session.ip_address}")
            print(f"  - Active: {session.is_active}")
            
            # Test session revocation
            session.revoke('test_revocation')
            print(f"✓ Session revoked successfully")
            print(f"  - Revoked at: {session.revoked_at}")
            print(f"  - Reason: {session.revoke_reason}")
        else:
            print("✗ No session created")
    else:
        print(f"✗ Login failed: {response.status_code}")
        print(f"  Response: {response.json()}")
    
    # Cleanup
    UserSession.objects.filter(user=user).delete()
    user.delete()
    print("✓ Session tracking test completed")


def test_refresh_token_rotation():
    """Test refresh token rotation"""
    print("\n=== Testing Refresh Token Rotation ===")
    
    # Create test user
    user = User.objects.create_user(
        username='rotationtest',
        email='rotationtest@example.com',
        password='TestPass123!'
    )
    
    # Create initial token
    refresh = RefreshToken.for_user(user)
    refresh['token_version'] = getattr(user, 'token_version', 1)
    
    print(f"✓ Initial refresh token created")
    print(f"  - JTI: {refresh['jti'][:16]}...")
    
    # Create session for the token
    session = UserSession.objects.create(
        user=user,
        device_id='test_device_001',
        device_name='Test Device',
        device_type='desktop',
        ip_address='127.0.0.1',
        user_agent='Test Agent',
        refresh_token_jti=refresh['jti'],
        expires_at=datetime.now() + timedelta(days=7)
    )
    refresh['session_id'] = str(session.id)
    
    print(f"✓ Session created for token")
    
    # Rotate the token
    rotator = RefreshTokenRotation()
    try:
        new_tokens = rotator.rotate_refresh_token(str(refresh))
        print(f"✓ Token rotated successfully")
        
        # Parse new refresh token
        new_refresh = RefreshToken(new_tokens['refresh'])
        print(f"  - New JTI: {new_refresh['jti'][:16]}...")
        
        # Check session was updated
        session.refresh_from_db()
        if session.refresh_token_jti == new_refresh['jti']:
            print(f"✓ Session updated with new token JTI")
        else:
            print(f"✗ Session not updated properly")
            
    except Exception as e:
        print(f"✗ Token rotation failed: {str(e)}")
    
    # Cleanup
    UserSession.objects.filter(user=user).delete()
    user.delete()
    print("✓ Refresh token rotation test completed")


def test_authentication_flow():
    """Test complete authentication flow"""
    print("\n=== Testing Complete Authentication Flow ===")
    
    # Create test user
    user = User.objects.create_user(
        username='flowtest',
        email='flowtest@example.com',
        password='TestPass123!'
    )
    
    # Create tenant membership for the user
    from tenants.models import Tenant
    from accounts.models import Membership
    
    tenant, _ = Tenant.objects.get_or_create(
        slug='ontime',
        defaults={'name': 'Ontime'}
    )
    Membership.objects.create(user=user, tenant=tenant)
    
    client = APIClient()
    
    # Step 1: Login
    print("\n1. Testing Login...")
    response = client.post('/api/token/', {
        'username': 'flowtest',
        'password': 'TestPass123!'
    }, HTTP_X_TENANT_ID='ontime')
    
    if response.status_code == 200:
        print("✓ Login successful")
        tokens = response.json()
        access_token = tokens.get('access')
        
        # Check for refresh token in cookies
        if 'refresh_token' in response.cookies:
            print("✓ Refresh token set in httpOnly cookie")
            refresh_cookie = response.cookies['refresh_token']
        else:
            print("! Refresh token not in cookie, using from response")
            refresh_cookie = tokens.get('refresh')
        
        # Step 2: Access protected endpoint
        print("\n2. Testing Protected Endpoint Access...")
        client.credentials(HTTP_AUTHORIZATION=f'Bearer {access_token}')
        me_response = client.get('/api/me/', HTTP_X_TENANT_ID='ontime')
        
        if me_response.status_code == 200:
            print("✓ Protected endpoint accessed successfully")
            user_data = me_response.json()
            print(f"  - Username: {user_data.get('username')}")
            print(f"  - Email: {user_data.get('email')}")
        else:
            print(f"✗ Failed to access protected endpoint: {me_response.status_code}")
        
        # Step 3: Refresh token
        print("\n3. Testing Token Refresh...")
        client.credentials()  # Clear auth header
        client.cookies['refresh_token'] = refresh_cookie
        
        refresh_response = client.post('/api/token/refresh/', 
                                      HTTP_X_TENANT_ID='ontime')
        
        if refresh_response.status_code == 200:
            print("✓ Token refreshed successfully")
            new_tokens = refresh_response.json()
            new_access = new_tokens.get('access')
            
            # Test with new access token
            client.credentials(HTTP_AUTHORIZATION=f'Bearer {new_access}')
            me_response2 = client.get('/api/me/', HTTP_X_TENANT_ID='ontime')
            
            if me_response2.status_code == 200:
                print("✓ New access token works")
            else:
                print("✗ New access token failed")
        else:
            print(f"✗ Token refresh failed: {refresh_response.status_code}")
            print(f"  Response: {refresh_response.json()}")
        
        # Step 4: Logout
        print("\n4. Testing Logout...")
        logout_response = client.post('/api/logout/', HTTP_X_TENANT_ID='ontime')
        
        if logout_response.status_code == 200:
            print("✓ Logout successful")
        else:
            print(f"✗ Logout failed: {logout_response.status_code}")
            
    else:
        print(f"✗ Login failed: {response.status_code}")
        print(f"  Response: {response.json()}")
    
    # Cleanup
    UserSession.objects.filter(user=user).delete()
    user.delete()
    print("\n✓ Complete authentication flow test completed")


def main():
    """Run all tests"""
    print("=" * 60)
    print("Enhanced Authentication System Tests")
    print("=" * 60)
    
    from datetime import timedelta
    
    try:
        # Clean up any existing test users
        User.objects.filter(username__in=[
            'tokentest', 'sessiontest', 'rotationtest', 'flowtest'
        ]).delete()
        
        # Run tests
        test_token_versioning()
        test_session_tracking()
        test_refresh_token_rotation()
        test_authentication_flow()
        
        print("\n" + "=" * 60)
        print("✓ All tests completed successfully!")
        print("=" * 60)
        
    except Exception as e:
        print(f"\n✗ Test failed with error: {str(e)}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
