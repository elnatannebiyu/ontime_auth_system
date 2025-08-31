#!/usr/bin/env python3
"""Create a test user via the registration API"""

import requests
import json

BASE_URL = "http://localhost:8000/api"

def create_test_user():
    print("Creating test user...")
    
    registration_data = {
        "username": "testuser@ontime.com",
        "email": "testuser@ontime.com",
        "password": "TestUser123!@#",
        "password2": "TestUser123!@#"
    }
    
    headers = {"X-Tenant-Id": "ontime"}
    response = requests.post(f"{BASE_URL}/register/", json=registration_data, headers=headers)
    
    if response.status_code in [200, 201]:
        print("✅ Test user created successfully!")
        print("   Email: testuser@ontime.com")
        print("   Password: TestUser123!@#")
        return True
    else:
        print(f"❌ Failed to create user: {response.status_code}")
        print(response.text)
        return False

if __name__ == "__main__":
    create_test_user()
