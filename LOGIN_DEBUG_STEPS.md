# Login Failure Debug Steps

**Your credentials are valid on backend** - User `leulsegedemekonen` exists, has password, is active, and is a member of tenant "ontime".

**But Flutter app gets:** `{"detail":"invalid username and password"}`

---

## Possible Issues

### Issue #1: Using Email Instead of Username

Your Flutter app sends:
```dart
await _authApi.login(
  tenantId: tenantId,
  username: email,  // Sending email as username
  password: password,
);
```

Backend expects either:
- Actual username: `leulsegedemekonen`
- OR email: `leulsegedemekonen@gmail.com`

**Test which one works:**
```bash
# Test with username
curl -X POST https://api.aitechnologiesplc.com/api/token/ \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: ontime" \
  -d '{"username":"leulsegedemekonen","password":"YOUR_PASSWORD"}'

# Test with email
curl -X POST https://api.aitechnologiesplc.com/api/token/ \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: ontime" \
  -d '{"username":"leulsegedemekonen@gmail.com","password":"YOUR_PASSWORD"}'
```

One of these should work. If email works but username doesn't, that's expected.

---

### Issue #2: Password Mismatch

The password you're entering in the app might not match what's in the database.

**Reset password to be sure:**
```bash
cd /srv/ontime/ontime_auth_system/authstack
python manage.py shell -c "
from django.contrib.auth.models import User
user = User.objects.get(email='leulsegedemekonen@gmail.com')
user.set_password('YOUR_NEW_PASSWORD')
user.save()
print('Password reset for', user.username)
"
```

Then try login with the new password.

---

### Issue #3: CSRF Token Blocking Login (NEW - Audit Fix #5)

We just enabled CSRF protection. The login endpoint might now require a CSRF token.

**Check if this is the issue:**
```bash
# Try login without CSRF token
curl -X POST https://api.aitechnologiesplc.com/api/token/ \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: ontime" \
  -d '{"username":"leulsegedemekonen@gmail.com","password":"YOUR_PASSWORD"}' \
  -v 2>&1 | grep -i csrf
```

If you see "CSRF verification failed", that's the issue.

**Solution:** Login endpoint should be exempt from CSRF (it's unauthenticated). Let me check:

---

### Issue #4: Missing X-Tenant-Id Header

Backend requires `X-Tenant-Id: ontime` header. Flutter app should send it via the interceptor.

**Verify in Flutter logs:**
Look for this in your debug output:
```
X-Tenant-Id: ontime
```

If missing, the tenant middleware will reject the request.

---

### Issue #5: Request Not Reaching Backend

The request might be failing at Nginx level (rate limiting, etc.).

**Check Nginx logs:**
```bash
# On server
sudo tail -f /var/log/nginx/access.log | grep "/api/token/"
```

Look for:
- `429` - Rate limited
- `403` - Forbidden (CSRF or other)
- `502/503` - Backend down

---

## Recommended Debug Steps (In Order)

### Step 1: Test Login via curl (Bypass Flutter)
```bash
curl -X POST https://api.aitechnologiesplc.com/api/token/ \
  -H "Content-Type: application/json" \
  -H "X-Tenant-Id: ontime" \
  -d '{"username":"leulsegedemekonen@gmail.com","password":"YOUR_ACTUAL_PASSWORD"}' \
  -v
```

**If this works:** Issue is in Flutter app  
**If this fails:** Issue is in backend/credentials

---

### Step 2: Check Flutter Request Headers
Add this debug logging to `api_client.dart` interceptor:

```dart
dio.interceptors.add(InterceptorsWrapper(onRequest:
    (RequestOptions options, RequestInterceptorHandler handler) async {
  // ... existing code ...
  
  // DEBUG: Print all headers for /token/ requests
  if (options.path.contains('/token/')) {
    debugPrint('[ApiClient] LOGIN REQUEST:');
    debugPrint('  URL: ${options.baseUrl}${options.path}');
    debugPrint('  Headers: ${options.headers}');
    debugPrint('  Data: ${options.data}');
  }
  
  return handler.next(options);
}));
```

This will show you exactly what's being sent.

---

### Step 3: Temporarily Disable CSRF for Login (Test)

If CSRF is blocking login, temporarily disable it:

```python
# In authstack/accounts/views.py
from django.views.decorators.csrf import csrf_exempt
from django.utils.decorators import method_decorator

@method_decorator(csrf_exempt, name='dispatch')  # TEMPORARY TEST
class TokenObtainPairWithCookieView(TokenObtainPairView):
    # ... existing code
```

Restart Django and test. If login works, CSRF is the issue.

**Don't forget to remove this after testing!**

---

### Step 4: Check for Rate Limiting

```bash
# Check if your IP is rate limited
sudo grep "limiting" /var/log/nginx/error.log | tail -20
```

If you see your IP being limited, wait a few minutes or temporarily increase the limit.

---

## Most Likely Issues (Ranked)

1. **Password mismatch** - You're entering wrong password in app
2. **CSRF blocking login** - New audit fix blocking unauthenticated POST
3. **Rate limiting** - Too many failed attempts
4. **Email vs username confusion** - App sends email but backend expects username

---

## Quick Test Matrix

| Test | Command | Expected Result |
|------|---------|-----------------|
| Backend validates user | ✅ Done | User exists, has password, is member |
| curl login with email | Run Step 1 | Should return access token |
| curl login with username | Replace email with `leulsegedemekonen` | Should return access token |
| Flutter app login | Use app | Currently failing |

**Run Step 1 (curl test) and paste the result here.** That will tell us if the issue is Flutter-specific or backend-wide.
