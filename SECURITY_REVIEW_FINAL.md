# Security Review - Email Login & Password Reset Features

**Date:** January 9, 2026  
**Scope:** New features added during audit remediation

---

## Features Added Today - Security Analysis

### 1. Email/Username Login Backend (`accounts/backends.py`)

**What it does:**
```python
class EmailOrUsernameBackend(ModelBackend):
    def authenticate(self, request, username=None, password=None, **kwargs):
        # Try username first (case-insensitive)
        user = User.objects.filter(username__iexact=username).first()
        # If not found, try email (case-insensitive)
        if user is None:
            user = User.objects.filter(email__iexact=username).first()
```

**Security considerations:**

#### ✅ SECURE:
- Case-insensitive lookup prevents enumeration via case variations
- Still requires correct password
- Inherits all Django security (password hashing, etc.)
- Works with existing rate limiting and brute-force protection (django-axes)

#### ⚠️ POTENTIAL CONCERNS:
**None** - This is a standard pattern and doesn't introduce new vulnerabilities.

---

### 2. Password Reset Flow

**Endpoints:**
- `POST /api/password-reset/request/` - Send reset email
- `POST /api/password-reset/confirm/` - Reset with token

**Current implementation review:**

#### ✅ SECURE Features:
1. **No user enumeration** - Always returns generic success message
2. **Email verification required** - Only verified emails can reset password
3. **One-time tokens** - 48-byte URL-safe tokens, single-use
4. **Time-limited** - Tokens expire in 1 hour
5. **All sessions revoked** - After password reset, all devices logged out
6. **Rate limiting** - Should be applied (check below)

#### ⚠️ MISSING: Rate Limiting on Password Reset

**Current code:** `RequestPasswordResetView` has no rate limiting decorator.

**Risk:** Attacker could spam password reset emails to a victim's address.

**Fix needed:**
```python
@method_decorator(ratelimit(key='ip', rate='3/h', method='POST'), name='dispatch')
class RequestPasswordResetView(APIView):
    # ... existing code
```

---

### 3. Duplicate Session Handling

**What it does:**
Catches `MultipleObjectsReturned` and keeps most recent session, deletes duplicates.

#### ✅ SECURE:
- Prevents 500 errors that could be exploited for DoS
- Automatically cleans up stale sessions
- Maintains session concurrency limit enforcement

#### ⚠️ CONSIDERATION:
**Logging needed** - Should log when duplicates are found (indicates potential issue).

**Add:**
```python
except UserSession.MultipleObjectsReturned:
    import logging
    logger = logging.getLogger(__name__)
    logger.warning(f'Multiple sessions found for user={self.user.id} device={device_id[:16]}')
    # ... existing cleanup code
```

---

## Critical Security Gaps to Address

### 🔴 GAP #1: Password Reset Rate Limiting (HIGH PRIORITY)

**Current state:** No rate limiting on `/api/password-reset/request/`

**Attack scenario:**
- Attacker floods victim's email with reset requests
- Email bombing / harassment
- Resource exhaustion

**Fix:**
<function_calls>
<invoke name="read_file">
<parameter name="file_path">/Users/elu/Documents/ontime_auth_system/authstack/accounts/views.py
