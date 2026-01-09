# Login Failure Diagnosis Guide

**Error:** `{"detail":"invalid username and password"}`

---

## 5 Possible Reasons for This Error

### ❌ Reason #1: Wrong Username/Email or Password
**Most common** - Credentials are incorrect.

**Test:**
```bash
# Try login via curl
curl -X POST https://api.aitechnologiesplc.com/api/token/ \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: ontime" \
  -d '{"username":"YOUR_EMAIL","password":"YOUR_PASSWORD"}' \
  -v
```

---

### ❌ Reason #2: User Not a Member of Tenant "ontime"
**Backend code:** `jwt_auth.py:162-164`
```python
if not Membership.objects.filter(user=self.user, tenant=tenant).exists():
    raise AuthenticationFailed('not_member_of_tenant')
```

**When:** User exists but has no Membership record for tenant "ontime".

**Fix:**
```bash
python manage.py shell -c "
from django.contrib.auth.models import User
from accounts.models import Membership
from tenants.models import Tenant

user = User.objects.get(email='YOUR_EMAIL')
tenant = Tenant.objects.get(slug='ontime')
Membership.objects.get_or_create(user=user, tenant=tenant)
print('Membership created!')
"
```

---

### ❌ Reason #3: Social-Only Account (No Password)
**Backend code:** `jwt_auth.py:129-131`
```python
if user is not None and not user.has_usable_password():
    raise AuthenticationFailed('password_auth_not_set')
```

**When:** Account created via Google/Apple, never set a password.

**Fix:** Use password reset flow to set a password, or login via social.

---

### ❌ Reason #4: AdminFrontend User Trying Mobile Login
**Backend code:** `jwt_auth.py:180-182`
```python
if is_admin_fe:
    raise AuthenticationFailed('invalid username and password')
```

**When:** User has "AdminFrontend" group but mobile app doesn't send `X-Admin-Login: 1` header.

**Fix:** Remove AdminFrontend role or use admin web interface.

---

### ❌ Reason #5: Tenant "ontime" Doesn't Exist
**Backend code:** `jwt_auth.py:158-160`
```python
try:
    tenant = Tenant.objects.get(slug=tenant_id)
except Tenant.DoesNotExist:
    raise AuthenticationFailed('unknown_tenant')
```

**Fix:**
```bash
python manage.py shell -c "
from tenants.models import Tenant
Tenant.objects.get_or_create(slug='ontime', defaults={'name': 'Ontime Ethiopia'})
print('Tenant created!')
"
```

---

## Complete Diagnostic Script

Run this on your server:

```bash
cd /srv/ontime/ontime_auth_system/authstack
python manage.py shell
```

```python
from django.contrib.auth.models import User
from accounts.models import Membership
from tenants.models import Tenant

email = 'YOUR_EMAIL_HERE'  # Replace with actual email

print('=== LOGIN FAILURE DIAGNOSIS ===\n')

# 1. Check user exists
user = User.objects.filter(email__iexact=email).first()
if not user:
    print(f'❌ PROBLEM: User with email {email} does NOT exist')
    print('   Solution: Register via /api/register/ first\n')
    exit()

print(f'✅ User exists: {user.username}')
print(f'   Email: {user.email}')
print(f'   Active: {user.is_active}')

# 2. Check password
has_password = user.has_usable_password()
print(f'   Has password: {has_password}')
if not has_password:
    print('   ❌ PROBLEM: Account is social-only (no password set)')
    print('   Solution: Use password reset to set a password\n')
    exit()

# 3. Check groups
groups = list(user.groups.values_list('name', flat=True))
print(f'   Groups: {groups}')
if 'AdminFrontend' in groups:
    print('   ❌ PROBLEM: User has AdminFrontend role')
    print('   Solution: This user can only login via admin web interface\n')
    exit()

# 4. Check tenant exists
try:
    tenant = Tenant.objects.get(slug='ontime')
    print(f'\n✅ Tenant exists: {tenant.name}')
except Tenant.DoesNotExist:
    print('\n❌ PROBLEM: Tenant "ontime" does not exist')
    print('   Creating tenant...')
    tenant = Tenant.objects.create(slug='ontime', name='Ontime Ethiopia')
    print(f'   ✅ Created: {tenant.name}\n')

# 5. Check membership
is_member = Membership.objects.filter(user=user, tenant=tenant).exists()
print(f'   Is member of ontime: {is_member}')
if not is_member:
    print('   ❌ PROBLEM: User is not a member of tenant "ontime"')
    print('   Creating membership...')
    Membership.objects.create(user=user, tenant=tenant)
    print('   ✅ Membership created!\n')
else:
    print('\n✅ ALL CHECKS PASSED - Login should work!')
    print('   If still failing, check:')
    print('   - Password is correct')
    print('   - Flutter app sends X-Tenant-Id: ontime header')
```

---

## Most Likely Issue

Based on your error, the most likely cause is **#2: Not a member of tenant "ontime"**.

This happens when:
- User was created directly in Django admin without membership
- User registered before multi-tenancy was implemented
- Membership record was deleted

**Quick fix:**
```bash
python manage.py shell -c "
from django.contrib.auth.models import User
from accounts.models import Membership
from tenants.models import Tenant

# Replace with your email
user = User.objects.get(email='YOUR_EMAIL')
tenant = Tenant.objects.get(slug='ontime')
Membership.objects.get_or_create(user=user, tenant=tenant)
print('Done! Try login again.')
"
```

---

## Password Reset Flow

1. User taps "Forgot Password?" on login screen
2. Enters email → Backend sends reset code
3. User enters code from email + new password
4. Backend validates and resets password
5. User can now login with new password

The backend endpoints are already implemented:
- `POST /api/password-reset/request/` - Send reset email
- `POST /api/password-reset/confirm/` - Confirm with token

I've created the Flutter UI in `password_reset_page.dart` - you just need to add navigation to it from your login page.

---

**Run the diagnostic script above to find the exact issue!**
