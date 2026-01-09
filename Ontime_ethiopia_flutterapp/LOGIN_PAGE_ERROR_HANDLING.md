# Login Page Error Handling Update

The login page needs to check both `data['detail']` and `data['error']` fields to properly detect social-only accounts.

## Current Code (Line 210-220)

```dart
final data = e.response?.data;
final rawDetail = (data is Map && data['detail'] != null)
    ? '${data['detail']}'
    : (e.message ?? '');
final detail = rawDetail.toString();

// Normalize common backend responses
String uiMsg = 'Login failed';
if (detail == 'password_auth_not_set') {
  uiMsg = 'This account was created with Google. Use "Continue with Google" or set a password first.';
}
```

## Updated Code (Replace with this)

```dart
final data = e.response?.data;
final rawDetail = (data is Map && data['detail'] != null)
    ? '${data['detail']}'
    : (e.message ?? '');
final detail = rawDetail.toString();

// Also check 'error' field for structured errors
final errorCode = (data is Map && data['error'] is String)
    ? data['error'] as String
    : '';

// Normalize common backend responses
String uiMsg = 'Login failed';
if (detail == 'password_auth_not_set' || errorCode == 'password_auth_not_set') {
  uiMsg = 'This account was created with Google. Use "Continue with Google" instead.';
  // Do NOT navigate to password reset - social accounts can't reset non-existent password
}
```

## Why This Matters

**Social-only accounts** (created via Google/Apple) don't have a password. They should:
- ✅ Login via Google/Apple sign-in
- ✅ Use "Enable Password" in app settings (if they want password login)
- ❌ NOT use "Forgot Password" (nothing to reset)

The backend now blocks password reset for these accounts and returns a clear error code.

## Update _forgotPassword Method

Also update the forgot password navigation to check if user has password:

```dart
Future<void> _forgotPassword() async {
  if (_loading) return;
  
  // Navigate to password reset page
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => SimplePasswordResetPage(
        tenantId: widget.tenantId,
      ),
    ),
  );
}
```

Change the import from:
```dart
import 'package:ontime_ethiopia_flutterapp/auth/password_reset_page.dart';
```

To:
```dart
import 'package:ontime_ethiopia_flutterapp/auth/simple_password_reset_page.dart';
```

This gives users the simple 6-digit OTP flow instead of the long token.
