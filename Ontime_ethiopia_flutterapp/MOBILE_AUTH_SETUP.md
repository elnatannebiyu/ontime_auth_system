# Flutter JWT Authentication with Django Backend

## Overview
This Flutter app integrates with the Django JWT authentication backend using HttpOnly cookies for refresh tokens and in-memory access tokens.

## Features
- ✅ JWT authentication with HttpOnly refresh cookies
- ✅ Automatic token refresh on 401 errors
- ✅ Cookie management with dio_cookie_manager
- ✅ Role-based access control
- ✅ Secure token storage pattern

## Dependencies Added
```yaml
dio: ^5.7.0                    # HTTP client
cookie_jar: ^4.0.8             # Cookie storage
dio_cookie_manager: ^3.1.1     # Automatic cookie handling
flutter_secure_storage: ^9.2.2 # Optional secure storage
collection: ^1.18.0            # Utility collections
```

## Project Structure
```
lib/
├── api_client.dart       # HTTP client with interceptors
├── auth_repository.dart  # Authentication logic
└── main.dart            # Demo UI with login/logout
```

## Setup Instructions

### 1. Install Dependencies
```bash
cd Ontime_ethiopia_flutterapp
flutter pub get
```

### 2. Configure Backend URL
Edit `lib/api_client.dart` and set the appropriate backend URL:

- **Android Emulator**: `http://10.0.2.2:8000`
- **iOS Simulator**: `http://localhost:8000`
- **Physical Device**: Use your machine's IP address
- **Production**: Use HTTPS URL

### 3. Start the Django Backend
```bash
cd ../authstack
python manage.py runserver 0.0.0.0:8000
```

### 4. Run the Flutter App
```bash
# For Android
flutter run

# For iOS (requires macOS)
flutter run -d ios

# List available devices
flutter devices
```

## Authentication Flow

### Login Process
1. User enters credentials
2. App sends POST to `/api/token/`
3. Backend returns access token in body
4. Backend sets HttpOnly refresh cookie
5. App stores access token in memory

### Token Refresh
1. API call receives 401 Unauthorized
2. Interceptor automatically calls `/api/token/refresh/`
3. Cookie jar sends refresh cookie automatically
4. Backend returns new access token
5. Original request is retried

### Logout
1. App calls `/api/logout/`
2. Backend clears refresh cookie
3. App clears access token from memory

## Security Considerations

### HttpOnly Cookies
- Refresh tokens stored as HttpOnly cookies
- Cannot be accessed by JavaScript/Dart code
- Automatically sent by cookie manager
- Protected from XSS attacks

### Access Token
- Stored only in app memory
- Never persisted to disk (unless explicitly needed)
- Short lifetime (15 minutes)
- Contains user roles and permissions

### Production Requirements
- Use HTTPS for secure cookies
- Enable certificate pinning for additional security
- Consider biometric authentication for app access

## API Integration

### Available Endpoints
```dart
// Authentication
POST /api/token/         // Login
POST /api/token/refresh/ // Refresh access token
POST /api/logout/        // Logout

// Protected endpoints
GET /api/me/            // User info
GET /api/admin-only/    // Admin role required
GET /api/users/         // List users (permission required)
```

### Error Handling
The app handles:
- Network errors
- 401 Unauthorized (triggers refresh)
- Invalid credentials
- Server errors

## Testing Credentials
Use these test accounts from the Django backend:
- Admin: `admin` / `password123` (Administrator role)
- User: Create via Django admin or API

## Android Specific Setup

### Network Security (for development)
If testing with HTTP in development, add to `android/app/src/main/AndroidManifest.xml`:
```xml
<application
    android:usesCleartextTraffic="true"
    ...>
```

### Internet Permission
Already included in the default Flutter template.

## iOS Specific Setup

### App Transport Security (for development)
If testing with HTTP in development, add to `ios/Runner/Info.plist`:
```xml
<key>NSAppTransportSecurity</key>
<dict>
    <key>NSAllowsArbitraryLoads</key>
    <true/>
</dict>
```

## Common Issues & Solutions

### Connection Refused
- Ensure Django is running on `0.0.0.0:8000` not `127.0.0.1:8000`
- Check firewall settings
- Verify the backend URL in `api_client.dart`

### 403 CSRF Failed
- CSRF is disabled for API endpoints in Django settings
- Ensure `CORS_ALLOW_CREDENTIALS = True` in Django

### Cookies Not Persisting
- Check that Django's `SESSION_COOKIE_SAMESITE` is configured correctly
- Ensure HTTPS in production for secure cookies

### Token Expired
- Normal behavior - the interceptor will handle refresh automatically
- If refresh fails, user must log in again

## Next Steps

### State Management
Consider adding state management for production:
```bash
flutter pub add provider
# or
flutter pub add riverpod
# or
flutter pub add bloc
```

### Persistent Storage
For optional token persistence:
```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

final storage = FlutterSecureStorage();
await storage.write(key: 'access_token', value: token);
```

### Biometric Authentication
Add biometric lock for app access:
```bash
flutter pub add local_auth
```

### Error Monitoring
Add crash reporting:
```bash
flutter pub add sentry_flutter
```

## Development Commands

```bash
# Clean build
flutter clean
flutter pub get

# Run with verbose logging
flutter run -v

# Build APK
flutter build apk

# Build iOS
flutter build ios

# Run tests
flutter test
```

## Architecture Notes

### Singleton Pattern
The `ApiClient` uses a singleton pattern to maintain a single Dio instance with consistent cookie storage.

### Interceptor Chain
1. Cookie Manager - Handles cookies automatically
2. Auth Interceptor - Adds Authorization header
3. Refresh Interceptor - Handles 401 and token refresh

### Repository Pattern
`AuthRepository` abstracts the authentication logic from the UI layer.

## Support
For issues or questions:
1. Check Django backend logs
2. Use Flutter DevTools for debugging
3. Monitor network traffic with proxy tools
4. Check cookie storage in app data

---
Last Updated: December 2024
Compatible with: Flutter 3.4+, Django 5.1+, DRF 3.15+
