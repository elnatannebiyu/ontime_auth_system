#!/usr/bin/env python3
"""Test immediate session revocation functionality"""
import requests
import json
import time
from datetime import datetime

BASE_URL = "http://localhost:8000/api"
TENANT_ID = "ontime"

# Test credentials
USERNAME = "test@example.com"
PASSWORD = "TestPass123!"

def print_section(title):
    """Print a section header"""
    print(f"\n{'='*60}")
    print(f" {title}")
    print('='*60)

def login(email, password, device_name="", device_id=None):
    """Login and return tokens"""
    print_section("1. LOGIN")
    headers = {
        "X-Tenant-Id": TENANT_ID,
        "X-Device-Name": device_name,
        "X-Device-Type": "test"
    }
    if device_id:
        headers["X-Device-Id"] = device_id
    
    response = requests.post(
        f"{BASE_URL}/token/",
        json={
            "username": email,  # Django expects 'username' field
            "password": password
        },
        headers=headers
    )
    
    if response.status_code == 200:
        data = response.json()
        print(f"✅ Login successful")
        print(f"   Access Token: {data['access'][:50]}...")
        return data['access']
    else:
        print(f"❌ Login failed: {response.status_code}")
        print(f"   Response: {response.text}")
        return None

def list_sessions(access_token):
    """List all active sessions"""
    print_section("2. LIST SESSIONS")
    
    response = requests.get(
        f"{BASE_URL}/sessions/",
        headers={
            "Authorization": f"Bearer {access_token}",
            "X-Tenant-Id": TENANT_ID
        }
    )
    
    if response.status_code == 200:
        data = response.json()
        # Handle both list and dict response formats
        if isinstance(data, dict):
            sessions = data.get('sessions', data.get('results', []))
        else:
            sessions = data
        print(f"✅ Found {len(sessions)} active session(s):")
        for session in sessions:
            if isinstance(session, str):
                # If sessions is a list of strings, skip detailed info
                print(f"\n   Session: {session}")
            else:
                print(f"\n   Session ID: {session.get('id', 'Unknown')}")
                print(f"   Device: {session.get('device_name', 'Unknown')} ({session.get('device_type', 'unknown')})")
                print(f"   IP: {session.get('ip_address', 'Unknown')}")
                print(f"   Created: {session.get('created_at', 'Unknown')}")
                print(f"   Is Current: {'✓' if session.get('is_current') else '✗'}")
        return sessions
    else:
        print(f"❌ Failed to list sessions: {response.status_code}")
        print(f"   Response: {response.text}")
        return []

def test_api_access(access_token, endpoint_name="/me/"):
    """Test if API access works with token"""
    response = requests.get(
        f"{BASE_URL}{endpoint_name}",
        headers={
            "Authorization": f"Bearer {access_token}",
            "X-Tenant-Id": TENANT_ID
        }
    )
    
    if response.status_code == 200:
        print(f"✅ API access successful to {endpoint_name}")
        return True
    elif response.status_code == 401:
        print(f"❌ API access denied (401) to {endpoint_name}")
        data = response.json() if response.text else {}
        if data.get('code') == 'SESSION_REVOKED':
            print(f"   Reason: Session has been revoked ✓")
        else:
            print(f"   Response: {data}")
        return False
    else:
        print(f"⚠️  Unexpected status {response.status_code} for {endpoint_name}")
        print(f"   Response: {response.text}")
        return False

def revoke_session(access_token, session_id):
    """Revoke a specific session"""
    print(f"\n   Revoking session {session_id}...")
    
    response = requests.delete(
        f"{BASE_URL}/sessions/{session_id}/",
        headers={
            "Authorization": f"Bearer {access_token}",
            "X-Tenant-Id": TENANT_ID
        }
    )
    
    if response.status_code == 200:
        print(f"   ✅ Session revoked successfully")
        return True
    else:
        print(f"   ❌ Failed to revoke session: {response.status_code}")
        print(f"      Response: {response.text}")
        return False

def main():
    """Main test flow"""
    print("\n" + "="*60)
    print(" TESTING IMMEDIATE SESSION REVOCATION")
    print("="*60)
    
    # Step 1: Login from two different "devices"
    print_section("SETUP: Create Two Sessions")
    # Step 1: Create two sessions (simulate two devices)
    print("\n📱 Device A: Logging in...")
    token_a = login(USERNAME, PASSWORD, "Device A", "device-a-id")
    if not token_a:
        print("Failed to create first session")
        return
    
    print("\n💻 Device B: Logging in...")
    token_b = login(USERNAME, PASSWORD, "Device B", "device-b-id")
    if not token_b:
        print("Failed to create second session")
        return
    
    # Step 2: List sessions from Device A
    sessions = list_sessions(token_a)
    if len(sessions) < 2:
        print("⚠️  Expected at least 2 sessions, found", len(sessions))
    
    # Find session B (the non-current one when using token A)
    session_b = None
    for session in sessions:
        if isinstance(session, dict) and not session.get('is_current'):
            session_b = session
            break
    
    if not session_b:
        print("❌ Could not find session B to revoke")
        return
    
    # Step 3: Test that both sessions work
    print_section("3. TEST BOTH SESSIONS WORK")
    print("\n📱 Device A:")
    test_api_access(token_a)
    print("\n💻 Device B:")
    test_api_access(token_b)
    
    # Step 4: Revoke Session B from Device A
    print_section("4. REVOKE SESSION B FROM DEVICE A")
    if revoke_session(token_a, session_b['id']):
        print("\n⏰ Waiting 2 seconds for revocation to propagate...")
        time.sleep(2)
        
        # Step 5: Test immediate revocation
        print_section("5. TEST IMMEDIATE REVOCATION")
        
        print("\n📱 Device A (should still work):")
        a_works = test_api_access(token_a)
        
        print("\n💻 Device B (should be revoked immediately):")
        b_works = test_api_access(token_b)
        
        # Summary
        print_section("RESULTS")
        if a_works and not b_works:
            print("✅ SUCCESS: Immediate session revocation is working!")
            print("   - Device A can still access the API")
            print("   - Device B was immediately logged out")
        elif a_works and b_works:
            print("⚠️  PARTIAL: Session revocation not immediate")
            print("   - Both devices can still access the API")
            print("   - Revocation may only take effect on token refresh")
        else:
            print("❌ UNEXPECTED: Check the results above")
    
    # Step 6: Verify session list
    print_section("6. VERIFY SESSION LIST")
    remaining_sessions = list_sessions(token_a)
    print(f"\n📊 Summary: {len(remaining_sessions)} active session(s) remaining")

if __name__ == "__main__":
    main()
