# Password Validation Error Handling Guide

**Issue:** When enabling password on social-only account, validation errors show as:
```
{"detail":"['This password is too common.', 'This password is entirely numeric.', 'Password must contain at least one uppercase letter.']"}
```

This is hard to parse and display to users.

---

## Backend Fix (Already Applied)

The backend now returns structured errors:

```python
# In EnablePasswordView (accounts/views.py:1213-1237)
try:
    validate_password(new_password, user=user)
except Exception as e:
    if hasattr(e, 'messages'):
        errors = list(e.messages)
        return Response({
            "detail": "Password does not meet requirements.",
            "errors": errors,  # Array of error messages
            "requirements": [
                "At least 8 characters",
                "At least one uppercase letter",
                "At least one lowercase letter",
                "At least one number",
                "At least one special character",
            ]
        }, status=400)
```

---

## Flutter Fix (Manual Update Required)

**File:** `lib/profile/profile_page.dart`

**Find this code** (around line 184):
```dart
} catch (_) {
  if (!mounted) return;
  setState(() {
    _loading = false;
    _error = 'Failed to enable password';
  });
}
```

**Replace with:**
```dart
} on DioException catch (e) {
  if (!mounted) return;
  
  String errorMsg = 'Failed to enable password';
  
  // Parse backend validation errors
  final data = e.response?.data;
  if (data is Map) {
    if (data['errors'] is List) {
      // Multiple validation errors
      final errors = (data['errors'] as List).cast<String>();
      errorMsg = 'Password requirements:\n• ' + errors.join('\n• ');
    } else if (data['detail'] is String) {
      errorMsg = data['detail'] as String;
    }
  }
  
  setState(() {
    _loading = false;
    _error = errorMsg;
  });
  
  // Show error in snackbar
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(errorMsg),
      backgroundColor: Colors.red,
      duration: const Duration(seconds: 5),
    ),
  );
} catch (_) {
  if (!mounted) return;
  setState(() {
    _loading = false;
    _error = 'Failed to enable password';
  });
}
```

**Also add import at top:**
```dart
import 'package:dio/dio.dart';
```

---

## Password Requirements

Your backend requires:
- ✅ At least 8 characters
- ✅ At least one uppercase letter (A-Z)
- ✅ At least one lowercase letter (a-z)
- ✅ At least one number (0-9)
- ✅ At least one special character (!@#$%^&*)
- ❌ Not too common (not in common password list)

**Valid examples:**
- `MyPass123!`
- `Secure@2024`
- `Root@1324`

**Invalid examples:**
- `password` - Too common, no uppercase, no number, no special char
- `12345678` - All numeric, no letters
- `Password` - No number, no special char

---

## User Experience After Fix

**Before (bad):**
```
Error: "['This password is too common.', 'This password is entirely numeric.']"
```

**After (good):**
```
Password requirements:
• This password is too common
• This password is entirely numeric
• Password must contain at least one uppercase letter
```

Much clearer for users!

---

## Rate Limiting (Answering Your Question)

**Password reset OTP requests:**
- **3 requests per hour** per IP address
- After 3 requests, you must wait **1 hour** before trying again
- Counter resets after 1 hour from first request

**Enable password endpoint:**
- **No rate limit** (requires authentication, so already protected)
- Can try as many times as needed until password meets requirements

---

## Deploy

```bash
cd /Users/elu/Documents/ontime_auth_system
git add authstack/accounts/views.py
git commit -m "Improve password validation error response format"
git push origin main

# Deploy
ssh root@75.119.138.31
cd /srv/ontime/ontime_auth_system/authstack
git pull origin main
sudo systemctl restart ontime.service
```

Then manually update the Flutter profile_page.dart with the error handling code above.
