#!/usr/bin/env python3
"""Test session management endpoints"""

import requests
import json

BASE_URL = "http://localhost:8000/api"

def test_sessions():
    # First, login to get tokens
    print("1. Testing login...")
    login_data = {
        "username": "testuser@ontime.com",
        "password": "TestUser123!@#"
    }
    
    session = requests.Session()
    headers = {"X-Tenant-Id": "ontime"}  # Add tenant header
    response = session.post(f"{BASE_URL}/token/", json=login_data, headers=headers)
    
    if response.status_code == 200:
        print("✅ Login successful")
        tokens = response.json()
        access_token = tokens.get('access')
        
        # Set authorization header with tenant
        headers = {
            "Authorization": f"Bearer {access_token}",
            "X-Tenant-Id": "ontime"
        }
        
        # Test listing sessions
        print("\n2. Testing session list...")
        response = session.get(f"{BASE_URL}/sessions/", headers=headers)
        if response.status_code == 200:
            sessions = response.json()
            print(f"✅ Found {len(sessions)} active session(s)")
            # Handle both list and dict response formats
            if isinstance(sessions, list):
                session_list = sessions
            else:
                session_list = [sessions] if isinstance(sessions, dict) else []
            
            for s in session_list:
                if isinstance(s, dict):
                    print(f"   - Device: {s.get('device_name', 'Unknown')} ({s.get('device_type', 'Unknown')})")  
                    print(f"     IP: {s.get('ip_address', 'Unknown')}")
                    print(f"     Current: {s.get('is_current', False)}")
                else:
                    print(f"   - Session ID: {s}")
        else:
            print(f"❌ Failed to list sessions: {response.status_code}")
            print(response.text)
    else:
        print(f"❌ Login failed: {response.status_code}")
        print(response.text)

if __name__ == "__main__":
    test_sessions()
