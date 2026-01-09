# Login Page Update - Add Password Reset Navigation

The `login_page.dart` file has encoding issues preventing automatic editing. Here's what you need to change manually:

---

## Step 1: Add Import

At the top of `lib/auth/login_page.dart`, add:

```dart
import 'password_reset_page.dart';
```

---

## Step 2: Replace _forgotPassword Method

Find the `_forgotPassword()` method (around line 140-165) and replace it with:

```dart
Future<void> _forgotPassword() async {
  if (_loading) return;
  
  // Navigate to dedicated password reset page
  Navigator.push(
    context,
    MaterialPageRoute(
      builder: (context) => PasswordResetPage(
        tenantId: widget.tenantId,
      ),
    ),
  );
}
```

---

## What This Does

**Before:**
- Clicking "Forgot Password?" validates email and sends reset request immediately
- Shows a toast/snackbar
- User stays on login page

**After:**
- Clicking "Forgot Password?" opens a dedicated password reset page
- User can enter email, receive code, and reset password in a guided flow
- Better UX with clear steps

---

## Complete Password Reset Flow

1. User taps "Forgot Password?" on login screen
2. **PasswordResetPage opens** (new)
3. User enters email → Backend sends reset code
4. User enters code from email + new password
5. Password reset confirmed
6. Auto-navigates back to login
7. User can login with new password

---

## Alternative: Keep Current Behavior

If you prefer the current simple toast approach, you don't need to change anything. The current implementation already works - it just sends the reset email and shows a confirmation message.

The dedicated page I created (`PasswordResetPage`) provides a more guided experience with:
- Clear two-step flow (request → confirm)
- Code input field
- Password confirmation
- Better error handling
- Visual feedback

Choose whichever UX you prefer!
