/// Global app configuration for API and tenant.
/// In production, prefer setting these via --dart-define at build time.
/// These constants provide a sane default that points to your current server.
library;

/// Default tenant slug used across the app.
const String kDefaultTenant = String.fromEnvironment(
  'TENANT_ID',
  defaultValue: 'ontime',
);

/// Default API base (scheme+host+port). Do NOT include the trailing /api.
/// Prefer HTTPS + domain in real production.
const String kDefaultApiBase = String.fromEnvironment(
  'API_BASE',
  defaultValue: 'http://10.0.2.2:8000',
);

/// Toggle verbose request header logging. Keep false in production.
const bool kEnableRequestHeaderLogging = bool.fromEnvironment(
  'LOG_REQUEST_HEADERS',
  defaultValue: false,
);

/// Google OAuth Web Client ID used on Android as serverClientId to obtain an ID token.
/// Set via: --dart-define=GOOGLE_OAUTH_WEB_CLIENT_ID=xxxx.apps.googleusercontent.com
const String kGoogleWebClientId = String.fromEnvironment(
  'GOOGLE_OAUTH_WEB_CLIENT_ID',
  defaultValue: '',
);
