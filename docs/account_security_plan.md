# Account & Session Security Plan

This document describes the next steps for implementing strong account ownership, verified email, and secure session management in Ontime.

## 1. Core Concepts

- **Verified account**
  - Each user has a unique `email`.
  - Backend tracks `email_verified: bool` on the user model.
  - Sensitive actions require a **verified email**.

- **Action tokens** (generic confirmation system)
  - Single model/logic for one-time actions:
    - `verify_email`
    - `confirm_logout_all`
    - `confirm_account_delete`
  - Fields:
    - `user`
    - `purpose`
    - `token` (random string)
    - `created_at`, `expires_at`
    - `used` (bool)

- **Email as final proof of ownership**
  - Only someone with access to the inbox can:
    - Confirm email verification
    - Confirm logout from all devices
    - Confirm account deletion

---

## 2. Backend Tasks (Django)

### 2.1 User model & /me endpoint

- Add `email_verified` boolean to the user model (default `False`).
- Expose it on the `/me` (current-user) API response:
  - `{"email": "user@example.com", "email_verified": true, ...}`

### 2.2 Email sending infrastructure

- Ensure SMTP/email settings are configured (e.g. `support@aitechnologiesplc.com` or `no-reply@ontime.et`).
- Implement a simple utility to send transactional emails (subject + HTML/text + link).

### 2.3 ActionToken model/logic

- Implement a reusable token system for user actions:
  - Purposes: `verify_email`, `confirm_logout_all`, `confirm_account_delete`.
  - Generate secure random tokens.
  - Enforce TTL (e.g. 30–60 minutes) and single use.

### 2.4 Email verification endpoints

- `POST /api/accounts/request-email-verification/`
  - Authenticated.
  - If `email_verified == False`, create `verify_email` token and send email.

- `GET /api/accounts/verify-email/?token=...`
  - Validate token (purpose, expiry, not used).
  - Mark `user.email_verified = True` and `token.used = True`.
  - Optionally render a simple confirmation page.

### 2.5 Logout-all confirmation endpoints

- `POST /api/accounts/request-logout-all-confirmation/`
  - Requires `email_verified == True`.
  - Creates `confirm_logout_all` token and sends email.

- `GET /api/accounts/confirm-logout-all/?token=...`
  - Validates token.
  - Calls the same logic as `RevokeAllSessionsView` to revoke all sessions for that user (optionally including current).
  - Marks token used.

### 2.6 Account deletion confirmation endpoints

- `POST /api/accounts/request-account-deletion/`
  - Requires authenticated & `email_verified == True`.
  - Creates `confirm_account_delete` token and sends email.

- `GET /api/accounts/confirm-account-delete/?token=...`
  - Validates token.
  - Deletes or soft-deletes the user and revokes all sessions.
  - Marks token used.

---

## 3. Frontend Tasks (Flutter)

### 3.1 Profile / /me integration

- Consume `/me` endpoint and store:
  - `email`
  - `email_verified`
- Show on Profile page:
  - Email + a badge:
    - **Verified** (green) if `email_verified`.
    - **Not verified** (warning) with a **"Verify email"** button otherwise.
- "Verify email" button:
  - Calls `POST /api/accounts/request-email-verification/`.
  - Shows "Check your email" message.

### 3.2 Session Security page: logout-all flow

- Change "Logout from all devices" behavior:
  - Show dialog: "We will send a confirmation link to your email."
  - Call `POST /api/accounts/request-logout-all-confirmation/`.
  - On success, show snackbar: "Check your email to confirm logout from all devices."
- Do **not** directly call `RevokeAllSessionsView` from the app anymore.

### 3.3 Profile page: account deletion

- Add "Delete account" section on Profile/settings:
  - Show strong warning text.
  - On confirm, call `POST /api/accounts/request-account-deletion/`.
  - Show "Check your email to confirm account deletion."

### 3.4 UI states based on verification

- If `email_verified == False`:
  - Show non-blocking warning banner on Profile and/or Session Security pages.
  - Optionally disable "Logout all devices" and "Delete account" buttons until user verifies email.

---

## 4. Security Notes

- All high-risk actions (logout-all, delete account) are gated by:
  - Being logged in **and**
  - Having a verified email **and**
  - Completing a one-time confirmation via link.
- If an attacker only steals a logged-in device but not the email inbox, they:
  - Cannot verify email.
  - Cannot confirm logout-all or account deletion.
- Tokens are single-use and time-limited to avoid replay or looping behaviors.

---

## 5. Implementation Order

1. Add `email_verified` to user model and expose it on `/me`.
2. Implement `ActionToken` model/logic and email utilities.
3. Implement email verification endpoints and test end-to-end.
4. Implement logout-all confirmation endpoints.
5. Implement account deletion confirmation endpoints.
6. Wire Flutter Profile page to show `email_verified` and trigger verification.
7. Update Session Security page to use the new logout-all confirmation flow.
8. Add "Delete account" flow on Profile page.
