# Flutter App Token Expiration & Force Logout Analysis

**Issue:** App sometimes won't get a token or has expired token, requiring sign out and re-login to work.

---

## All Scenarios That Cause Force Logout (Require Re-Login)

### 1. **Refresh Cookie Missing or Deleted** ❌ CRITICAL
**Location:** `api_client.dart:484-490`
```dart
if (_accessToken == null && refreshCookies.isEmpty) {
  debugPrint('[ApiClient] No access token and no refresh cookie. Forcing logout.');
  _forceLogout();
}
```

**When this happens:**
- App was uninstalled/reinstalled (cookies cleared)
- User cleared app data/cache
- Cookie storage failed to persist
- Backend cleared the cookie (unlikely)

**Fix:** Cannot auto-recover - user MUST re-login

---

### 2. **Refresh Token Returns 401 (Invalid/Expired Session)** ❌ CRITICAL
**Location:** `api_client.dart:543-556`
```dart
if (e.response?.statusCode == 401) {
  final detail = (data is Map && data['detail'] is String) ? data['detail'] as String : '';
  if (detail.contains('Session not found or inactive') ||
      detail.contains('Session has expired') ||
      detail.contains('Token is invalid or expired') ||
      detail.contains('token_not_valid') ||
      detail.contains('Refresh token not found')) {
    _forceLogout();
  }
}
```

**When this happens:**
- **Session revoked on backend** (password change, logout from another device, admin action)
- **Session expired** (7 days passed since last refresh)
- **Session limit exceeded** (NEW: user logged in from 6+ devices, oldest session auto-revoked)
- **Token blacklisted** (backend security action)
- **Database session deleted** (admin cleanup, migration)

**Backend causes:**
- `SessionRevocationMiddleware` detects revoked session
- `TokenSessionBindingMiddleware` detects token-session mismatch (NEW audit fix)
- `MAX_CONCURRENT_SESSIONS` limit exceeded (NEW audit fix)

**Fix:** Cannot auto-recover - user MUST re-login

---

### 3. **Session Revoked Code from Backend** ❌ CRITICAL
**Location:** `api_client.dart:643-653` (in `_TokenRefreshInterceptor`)
```dart
final code = (data is Map && data['code'] is String) ? data['code'] as String : '';
final revoked = code == 'SESSION_REVOKED';
final inactive = code == 'user_inactive';
if (revoked || inactive) {
  client._forceLogout();
}
```

**When this happens:**
- Backend explicitly sends `SESSION_REVOKED` code
- User account is deactivated (`user_inactive`)
- Session was revoked via `/api/sessions/revoke-all/`
- Admin revoked the session

**Fix:** Cannot auto-recover - user MUST re-login

---

### 4. **No Refresh Cookie Available When 401 Occurs** ❌ CRITICAL
**Location:** `api_client.dart:657-660` (in interceptor)
```dart
if (!await client._hasRefreshCookie()) {
  // No way to refresh; force logout to clear bad token state
  client._forceLogout();
  return handler.reject(err);
}
```

**When this happens:**
- Access token expired but refresh cookie is gone
- Cookie was deleted by OS/browser
- Cookie expired (should match refresh token lifetime)
- Cookie path mismatch (backend sends `/api/token/refresh/` but client expects `/`)

**Fix:** Cannot auto-recover - user MUST re-login

---

### 5. **Token Injection Detected (NEW - Audit Fix #6 & #7)** ❌ NEW
**Location:** Backend `accounts/middleware.py:127-136` (TokenSessionBindingMiddleware)
```python
if str(session.user_id) != str(token_user_id):
    logger.warning(f'[TokenSessionBinding] Token injection detected')
    return JsonResponse({
        'error': 'Token-session mismatch detected',
        'code': 'TOKEN_INJECTION_DETECTED'
    }, status=401)
```

**When this happens:**
- User manually edited access token in storage (dev/testing)
- Token was copied from another device/user
- Clock skew caused session_id mismatch
- **Bug in token generation** (session_id not properly embedded)

**Fix:** Cannot auto-recover - user MUST re-login

---

### 6. **Refresh Fails with 401 in Interceptor** ❌ CRITICAL
**Location:** `api_client.dart:685-693` (in interceptor error handler)
```dart
} else if (e.response?.statusCode == 401) {
  debugPrint('[ApiClient] Interceptor: refresh failed with 401; forcing logout');
  if (!pathLower.contains('/logout/')) {
    client._forceLogout();
  }
}
```

**When this happens:**
- Refresh attempt failed with 401
- Cascading failure from scenarios #1-5 above
- Network returned 401 for any reason during refresh

**Fix:** Cannot auto-recover - user MUST re-login

---

## Scenarios That DON'T Force Logout (Recoverable)

### ✅ Access Token Expired (But Refresh Cookie Valid)
**Location:** `api_client.dart:444-456`
```dart
final exp = JwtDecoder.getExpirationDate(token);
if (exp.isBefore(now.add(skew))) {
  await _refreshAccess();  // Auto-refresh, no logout
}
```

**When this happens:**
- Access token expired (15 minutes)
- Refresh cookie still valid (7 days)

**Fix:** ✅ Auto-recovers via `ensureFreshAccess()` preflight

---

### ✅ Rate Limited (429)
**Location:** `api_client.dart:559-562`
```dart
if (e.response?.statusCode == 429) {
  debugPrint('[ApiClient] Refresh 429 received; applying backoff');
  _refreshBackoffUntil = DateTime.now().add(const Duration(minutes: 5));
}
```

**When this happens:**
- Too many refresh attempts
- Backend rate limiting triggered

**Fix:** ✅ Backs off for 5 minutes, then retries (no logout)

---

### ✅ Network/Connection Errors
**Location:** `api_client.dart:610-613`
```dart
if (err.type == DioExceptionType.connectionError || err.error is SocketException) {
  return handler.next(err);  // No logout
}
```

**When this happens:**
- No internet connection
- Server unreachable
- DNS failure

**Fix:** ✅ Shows error, user can retry (no logout)

---

## Root Causes Summary

| Scenario | Frequency | Cause | Auto-Recoverable? |
|----------|-----------|-------|-------------------|
| **Refresh cookie missing** | High | App reinstall, cache clear | ❌ No |
| **Session expired (7 days)** | Medium | User inactive for 7+ days | ❌ No |
| **Session revoked** | Medium | Password change, logout elsewhere | ❌ No |
| **Session limit exceeded** | NEW - Medium | Logged in from 6+ devices | ❌ No |
| **Token-session mismatch** | NEW - Low | Token injection, clock skew | ❌ No |
| **Access token expired** | High | Normal (15 min lifetime) | ✅ Yes |
| **Rate limited** | Low | Too many refresh attempts | ✅ Yes |
| **Network error** | High | Offline, server down | ✅ Yes |

---

## Known Issues & Edge Cases

### Issue #1: Refresh Cookie Path Mismatch
**Problem:** Backend sets cookie with `path=/api/token/refresh/` but client might expect `/`

**Check in backend:**
```python
# authstack/accounts/views.py:66-75
def set_refresh_cookie(response: Response, refresh: str):
    response.set_cookie(
        key=REFRESH_COOKIE_NAME,
        value=refresh,
        httponly=True,
        secure=not settings.DEBUG,
        samesite="Lax",
        path=REFRESH_COOKIE_PATH,  # Check this value
        max_age=60 * 60 * 24 * 7,
    )
```

**Current value:** `REFRESH_COOKIE_PATH = "/api/token/refresh/"`

**Potential fix:** Change to `path="/"` so cookie is sent with all requests

---

### Issue #2: Multiple Refresh Cookies
**Problem:** App detects and dedupes multiple refresh cookies, but this shouldn't happen

**Location:** `api_client.dart:492-508`
```dart
if (refreshCookies.length > 1) {
  // Choose the most recent by expires
  refreshCookies.sort(...);
  final winner = refreshCookies.first;
  await cookieJar.delete(refreshUri);
  await cookieJar.saveFromResponse(refreshUri, [winner]);
}
```

**Root cause:** Multiple logins without proper cookie cleanup, or cookie path issues

---

### Issue #3: Clock Skew
**Problem:** If device clock is wrong, JWT expiration checks fail

**Location:** `api_client.dart:453-456`
```dart
final exp = JwtDecoder.getExpirationDate(token);
if (exp.isBefore(now.add(skew))) {
  await _refreshAccess();
}
```

**Impact:** If device clock is in the future, token appears expired even when valid

---

### Issue #4: Refresh Cooldown Too Aggressive
**Problem:** 60-second cooldown after refresh might prevent legitimate retries

**Location:** `api_client.dart:74-76`
```dart
final Duration _postRefreshCooldown = const Duration(seconds: 60);
```

**Impact:** If refresh fails, user must wait 60 seconds before next attempt

---

### Issue #5: Session Limit Exceeded (NEW - Audit Fix #2)
**Problem:** User logs in from 6th device, oldest session is auto-revoked

**Backend:** `authstack/accounts/jwt_auth.py:232-254`
```python
if active_sessions.count() > max_sessions:
    sessions_to_revoke = active_sessions[max_sessions:]
    for old_session in sessions_to_revoke:
        old_session.revoke('session_limit_exceeded')
```

**Impact:** If user has app open on 5 devices and logs in on 6th, the oldest device gets force-logged out

---

## Recommended Fixes

### Fix #1: Better Logging for Diagnostics
Add more detailed logging to identify exact failure point:

```dart
void _forceLogout() async {
  final hadToken = _accessToken != null && _accessToken!.isNotEmpty;
  final hasRefresh = await _hasRefreshCookie();
  
  debugPrint('[ApiClient] FORCE LOGOUT TRIGGERED:');
  debugPrint('  - Had access token: $hadToken');
  debugPrint('  - Has refresh cookie: $hasRefresh');
  debugPrint('  - Stack trace: ${StackTrace.current}');
  
  // ... rest of logout logic
}
```

### Fix #2: Graceful Session Limit Notification
When session is revoked due to limit, show user-friendly message:

```dart
if (code == 'SESSION_REVOKED') {
  final reason = (data is Map && data['reason'] is String) ? data['reason'] : '';
  if (reason == 'session_limit_exceeded') {
    client._notify('You were logged out because you signed in from another device. (Max 5 devices)');
  }
  client._forceLogout();
}
```

### Fix #3: Retry Logic for Transient Failures
Add exponential backoff for refresh failures:

```dart
int _refreshFailureCount = 0;

Future<void> _refreshAccess() async {
  try {
    // ... existing refresh logic
    _refreshFailureCount = 0;  // Reset on success
  } catch (e) {
    _refreshFailureCount++;
    if (_refreshFailureCount >= 3) {
      // After 3 failures, force logout
      _forceLogout();
    } else {
      // Exponential backoff
      final backoff = Duration(seconds: 2 << _refreshFailureCount);
      _refreshBackoffUntil = DateTime.now().add(backoff);
    }
    rethrow;
  }
}
```

### Fix #4: Validate Refresh Cookie Before Preflight
Prevent unnecessary refresh attempts when cookie is missing:

```dart
Future<void> ensureFreshAccess({Duration skew = const Duration(seconds: 60)}) async {
  final token = _accessToken;
  if (token == null || token.isEmpty) return;
  
  // NEW: Check if refresh cookie exists BEFORE checking expiration
  if (!await _hasRefreshCookie()) {
    debugPrint('[ApiClient] No refresh cookie available, skipping preflight');
    return;  // Don't attempt refresh if we know it will fail
  }
  
  // ... rest of existing logic
}
```

### Fix #5: Change Refresh Cookie Path to Root
**Backend change:** `authstack/authstack/settings.py`
```python
# Change from:
REFRESH_COOKIE_PATH = "/api/token/refresh/"

# To:
REFRESH_COOKIE_PATH = "/"
```

This ensures the cookie is sent with all requests, not just refresh endpoint.

---

## Testing Checklist

To identify which scenario is causing your issue:

```dart
// Add this debug helper to ApiClient
Future<Map<String, dynamic>> debugTokenState() async {
  final hasAccess = _accessToken != null && _accessToken!.isNotEmpty;
  final hasRefresh = await _hasRefreshCookie();
  
  String? tokenExp;
  bool? tokenExpired;
  if (_accessToken != null) {
    try {
      final exp = JwtDecoder.getExpirationDate(_accessToken!);
      tokenExp = exp.toIso8601String();
      tokenExpired = exp.isBefore(DateTime.now());
    } catch (_) {
      tokenExp = 'invalid';
    }
  }
  
  return {
    'has_access_token': hasAccess,
    'has_refresh_cookie': hasRefresh,
    'access_token_expires': tokenExp,
    'access_token_expired': tokenExpired,
    'refresh_backoff_until': _refreshBackoffUntil?.toIso8601String(),
    'last_refresh_attempt': _lastRefreshAttemptAt?.toIso8601String(),
  };
}
```

Then in your app, add a debug screen:
```dart
// Debug button in settings
ElevatedButton(
  onPressed: () async {
    final state = await ApiClient().debugTokenState();
    print('Token State: $state');
  },
  child: Text('Debug Token State'),
)
```

---

## Most Likely Causes (Ranked by Probability)

1. **Session limit exceeded (NEW)** - You logged in from 6+ devices
2. **Refresh cookie missing** - App cache cleared or reinstalled
3. **Session expired** - 7 days passed without app use
4. **Password changed** - All sessions revoked
5. **Token-session mismatch (NEW)** - Audit fix detecting anomaly
6. **Backend session cleanup** - Admin action or migration

---

## Immediate Action Items

1. **Add better logging** - Implement Fix #1 to see exact failure point
2. **Check session count** - See if you're hitting the 5-device limit
3. **Verify refresh cookie path** - Ensure backend sends cookie with `path=/`
4. **Monitor backend logs** - Check for SESSION_REVOKED or TOKEN_INJECTION_DETECTED

---

## Backend Session Check

Run this on your server to see current sessions:

```bash
cd /srv/ontime/ontime_auth_system/authstack
python manage.py shell -c "
from accounts.models import UserSession
from django.contrib.auth.models import User

# Check your user's active sessions
user = User.objects.get(username='YOUR_USERNAME')
sessions = UserSession.objects.filter(user=user, is_active=True).order_by('-last_activity')

print(f'Active sessions for {user.username}: {sessions.count()}')
for s in sessions[:10]:
    print(f'  - Device: {s.device_name or s.device_id[:16]} | Last: {s.last_activity} | IP: {s.ip_address}')

# Check revoked sessions
revoked = UserSession.objects.filter(user=user, is_active=False).order_by('-revoked_at')[:5]
print(f'\nRecently revoked sessions: {revoked.count()}')
for s in revoked:
    print(f'  - Reason: {s.revoke_reason} | Revoked: {s.revoked_at}')
"
```

This will tell you if you're hitting the session limit or if sessions are being revoked for other reasons.

---

**END OF ANALYSIS**
