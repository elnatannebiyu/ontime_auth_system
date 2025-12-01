// ignore_for_file: unused_element

import 'dart:async';
import 'dart:convert';
import 'dart:io' show SocketException, Platform;
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'auth/services/device_info_service.dart';
import 'config.dart';

/// Configure backend origin per platform with environment overrides
/// Priority:
/// 1) Dart-define LAN_API_BASE (e.g., http://192.168.1.50:8000)
/// 2) ANDROID_NET_MODE (emulator | device_local | auto)
/// 3) Platform defaults
const String _envLanBase =
    String.fromEnvironment('LAN_API_BASE', defaultValue: '');
const String _envAndroidMode =
    String.fromEnvironment('ANDROID_NET_MODE', defaultValue: 'auto');

String _resolveApiBase() {
  // If explicit LAN provided, use it universally
  if (_envLanBase.isNotEmpty) {
    return _envLanBase;
  }
  // If a default API base is provided via config.dart, prefer that
  if (kDefaultApiBase.isNotEmpty) {
    return kDefaultApiBase;
  }
  if (Platform.isAndroid) {
    switch (_envAndroidMode) {
      case 'emulator':
        return 'http://10.0.2.2:8000';
      case 'device_local':
        // Server running in Termux on the same phone
        return 'http://127.0.0.1:8000';
      case 'auto':
      default:
        // Default to Android emulator host mapping
        return 'http://10.0.2.2:8000';
    }
  }
  if (Platform.isIOS || Platform.isMacOS) {
    return 'http://localhost:8000';
  }
  // Fallback for other platforms
  return 'http://localhost:8000';
}

String kApiBase = _resolveApiBase();

class ApiClient {
  final Dio dio;
  CookieJar cookieJar;
  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  bool _initialized = false;
  String? _accessToken; // in-memory; persisted securely for restore
  String? _tenantSlug; // e.g., "default", sent via X-Tenant-Id
  void Function()? _onForceLogout; // optional app-level handler
  void Function(String message)?
      _onNotify; // optional UI notifier (e.g., snackbar)
  void Function(String message, String? storeUrl)?
      _onUpdateRequired; // optional: show blocking modal/update CTA
  Completer<void>? _refreshing; // single-flight guard for refresh
  // Backoff/cooldown to avoid frequent refresh attempts
  DateTime? _refreshBackoffUntil; // when set, skip refresh until this time
  DateTime?
      _lastRefreshAttemptAt; // throttle preflight immediately after an attempt
  final Duration _postRefreshCooldown = const Duration(
      seconds:
          60); // after a refresh (or attempt), skip preflight for this long

  // Short-lived cache for current-user payload to avoid double fetching
  Map<String, dynamic>? _lastMe;
  DateTime? _lastMeAt;

  static final ApiClient _singleton = ApiClient._internal();
  factory ApiClient() => _singleton;

  ApiClient._internal()
      : dio = Dio(BaseOptions(
          baseUrl: "$kApiBase/api",
          connectTimeout: const Duration(seconds: 20),
          receiveTimeout: const Duration(seconds: 20),
          headers: {
            'Accept': 'application/json',
          },
          // Treat 426 (Upgrade Required) as a handled response so Dio won't throw
          validateStatus: (code) {
            if (code == null) return false;
            if (code == 426) return true;
            // Also accept 401/403 to allow interceptors to handle
            if (code == 401 || code == 403) return true;
            return code >= 200 && code < 400;
          },
        )),
        cookieJar = CookieJar() {
    dio.interceptors.add(CookieManager(cookieJar));

    // Dev logging: print requests/responses/errors to console
    if (kDebugMode || kEnableRequestHeaderLogging) {
      dio.interceptors.add(LogInterceptor(
        request: true,
        requestBody: true,
        requestHeader: kEnableRequestHeaderLogging,
        responseBody: true,
        responseHeader: false,
        error: true,
        logPrint: (obj) {
          // Redact auth header if present
          final text = obj.toString().replaceAll(
              RegExp(r'Authorization: Bearer [^\n]+'),
              'Authorization: Bearer <redacted>');
          debugPrint(text);
        },
      ));
    }

    // ---- Device identity helpers ----
    Future<String> deviceId() => DeviceInfoService.getDeviceId();
    Future<String> deviceName() => DeviceInfoService.getDeviceName();
    Future<Map<String, String>> deviceHeaders() async {
      final std = await DeviceInfoService.getStandardDeviceHeaders();
      final extra = await DeviceInfoService.getDeviceHeaders();
      return {...std, ...extra};
    }

    // Attach Authorization, tenant, and device headers
    dio.interceptors.add(InterceptorsWrapper(onRequest:
        (RequestOptions options, RequestInterceptorHandler handler) async {
      // Lazy init ensures persisted cookies and stored access token are loaded
      if (!_initialized) {
        await ensureInitialized();
      }
      // Preflight: if token is present and near expiry, attempt refresh
      // BUT skip when hitting auth endpoints themselves to avoid recursion
      try {
        final path = options.path; // may be relative like '/token/refresh/'
        final lower = path.toLowerCase();
        final isAuthEndpoint = lower.contains('/token/refresh/') ||
            lower.contains('/token/') ||
            lower.contains('/logout/');
        if (!isAuthEndpoint) {
          await ensureFreshAccess(skew: const Duration(seconds: 60));
        }
      } catch (_) {
        // ignore here; normal 401 flow/interceptor will handle failures
      }
      if (_accessToken != null) {
        options.headers['Authorization'] = 'Bearer $_accessToken';
      }
      if (_tenantSlug != null && _tenantSlug!.isNotEmpty) {
        options.headers['X-Tenant-Id'] = _tenantSlug;
      }
      try {
        final std = await DeviceInfoService.getStandardDeviceHeaders();
        final extra = await DeviceInfoService.getDeviceHeaders();
        options.headers.addAll(std);
        options.headers.addAll(extra);
      } catch (_) {}
      return handler.next(options);
    }));

    // Handle 401 -> refresh -> retry
    dio.interceptors.add(_TokenRefreshInterceptor(this));

    // Normalize backend version-enforcement (426 or explicit APP_UPDATE_REQUIRED code)
    // to a friendly notification that can show a blocking update dialog.
    dio.interceptors.add(InterceptorsWrapper(
      onResponse:
          (Response response, ResponseInterceptorHandler handler) async {
        final data = response.data;
        // If the backend explicitly signals that the session has been revoked,
        // force logout immediately. Note: validateStatus treats 401 as a
        // handled status, so this must be checked in onResponse, not only
        // in onError.
        if (response.statusCode == 401 &&
            data is Map &&
            data['code'] == 'SESSION_REVOKED') {
          _forceLogout();
          return handler.next(response);
        }
        // Case 1: HTTP 426 Upgrade Required (version enforcement middleware)
        if (response.statusCode == 426) {
          try {
            final msg = (data is Map && data['message'] is String)
                ? data['message'] as String
                : 'Please update the app to continue.';
            // Clear any existing credentials to prevent further use
            _forceLogout();
            final storeUrl = (data is Map && data['store_url'] is String)
                ? data['store_url'] as String
                : null;
            final cb = _onUpdateRequired;
            if (cb != null) cb(msg, storeUrl);
          } catch (_) {}
        } else if (data is Map && data['code'] == 'APP_UPDATE_REQUIRED') {
          // Case 2: JSON payload explicitly signalling that this endpoint
          // requires an app update (e.g., social login or other auth flows).
          try {
            final msg = (data['message'] is String)
                ? data['message'] as String
                : 'This version is no longer supported. Please update to continue.';
            final storeUrl = (data['store_url'] is String)
                ? data['store_url'] as String
                : null;
            final cb = _onUpdateRequired;
            if (cb != null) cb(msg, storeUrl);
          } catch (_) {}
        }
        return handler.next(response);
      },
      onError: (DioException err, ErrorInterceptorHandler handler) async {
        final data = err.response?.data;
        // 426 from any endpoint enforces an app update
        if (err.response?.statusCode == 426) {
          try {
            final msg = (data is Map && data['message'] is String)
                ? data['message'] as String
                : 'Please update the app to continue.';
            // Clear any existing credentials to prevent further use
            _forceLogout();
            final storeUrl = (data is Map && data['store_url'] is String)
                ? data['store_url'] as String
                : null;
            final cb = _onUpdateRequired;
            if (cb != null) cb(msg, storeUrl);
          } catch (_) {}
        } else if (data is Map && data['code'] == 'APP_UPDATE_REQUIRED') {
          // Some endpoints may return APP_UPDATE_REQUIRED with non-426 status codes.
          try {
            final msg = (data['message'] is String)
                ? data['message'] as String
                : 'This version is no longer supported. Please update to continue.';
            final storeUrl = (data['store_url'] is String)
                ? data['store_url'] as String
                : null;
            final cb = _onUpdateRequired;
            if (cb != null) cb(msg, storeUrl);
          } catch (_) {}
        }
        return handler.next(err);
      },
    ));
  }

  void setAccessToken(String? token) {
    _accessToken = token;
    if (token == null || token.isEmpty) {
      _secure.delete(key: 'access_token');
    } else {
      _secure.write(key: 'access_token', value: token);
    }
  }

  String? getAccessToken() {
    return _accessToken;
  }

  void setTenant(String? tenantSlug) {
    _tenantSlug = tenantSlug;
  }

  // Initialize default tenant from config, if not set elsewhere
  void ensureDefaultTenant() {
    if ((_tenantSlug == null || _tenantSlug!.isEmpty) &&
        kDefaultTenant.isNotEmpty) {
      _tenantSlug = kDefaultTenant;
    }
  }

  /// Allows changing the base URL at runtime (e.g., user setting or detection)
  void setBaseUrl(String base) {
    if (base.isEmpty) return;
    if (!base.startsWith('http')) return;
    dio.options.baseUrl = base.endsWith('/api') ? base : "$base/api";
    kApiBase = base; // keep global in sync for diagnostics
  }

  String? get tenant => _tenantSlug;

  // --- Me cache helpers ---
  void setLastMe(Map<String, dynamic> me) {
    _lastMe = Map<String, dynamic>.from(me);
    _lastMeAt = DateTime.now();
    try {
      final encoded = jsonEncode(_lastMe);
      _secure.write(key: 'last_me', value: encoded);
      _secure.write(key: 'last_me_at', value: _lastMeAt!.toIso8601String());
    } catch (_) {}
  }

  Map<String, dynamic>? getFreshMe(
      {Duration ttl = const Duration(seconds: 5)}) {
    if (_lastMe == null || _lastMeAt == null) return null;
    if (DateTime.now().difference(_lastMeAt!) > ttl) return null;
    return Map<String, dynamic>.from(_lastMe!);
  }

  /// Returns the last known user payload regardless of age.
  /// Useful for offline/profile screens that want "best effort" data.
  Map<String, dynamic>? getCachedMe() {
    if (_lastMe == null) return null;
    return Map<String, dynamic>.from(_lastMe!);
  }

  /// Register a callback invoked when we must force logout (e.g., missing refresh cookie or session revoked)
  void setForceLogoutHandler(void Function()? handler) {
    _onForceLogout = handler;
  }

  /// Register a lightweight notifier to surface user messages (e.g., offline snackbar)
  void setNotifier(void Function(String message)? handler) {
    _onNotify = handler;
  }

  /// Register a callback invoked when the backend enforces an app update (HTTP 426)
  void setUpdateRequiredHandler(
      void Function(String message, String? storeUrl)? handler) {
    _onUpdateRequired = handler;
  }

  void _forceLogout() async {
    // Only surface a logout message/navigation if we previously had an access token
    final hadToken = _accessToken != null && _accessToken!.isNotEmpty;
    debugPrint('[ApiClient] Forcing logout: clearing access token and cookies');
    _accessToken = null;
    _lastMe = null;
    _lastMeAt = null;
    try {
      await cookieJar.deleteAll();
      await _secure.delete(key: 'access_token');
      await _secure.delete(key: 'last_me');
      await _secure.delete(key: 'last_me_at');
    } catch (_) {}
    final cb = _onForceLogout;
    if (cb != null && hadToken) {
      debugPrint(
          '[ApiClient] Invoking force-logout callback (navigation to /login)');
      cb();
    } else {
      debugPrint('[ApiClient] No force-logout callback registered');
    }
  }

  void _notify(String message) {
    final cb = _onNotify;
    if (cb != null) cb(message);
  }

  Future<Response<T>> post<T>(String path, {data, Options? options}) {
    return dio.post<T>(path, data: data, options: options);
  }

  Future<Response<T>> get<T>(String path,
      {Map<String, dynamic>? queryParameters, Options? options}) {
    return dio.get<T>(path, queryParameters: queryParameters, options: options);
  }

  Future<Response<T>> put<T>(String path, {data, Options? options}) {
    return dio.put<T>(path, data: data, options: options);
  }

  Future<Response<T>> delete<T>(String path, {data, Options? options}) {
    return dio.delete<T>(path, data: data, options: options);
  }

  // ---- Initialization & token management ----
  Future<void> ensureInitialized() async {
    if (_initialized) return;
    try {
      final dir = await getApplicationSupportDirectory();
      final cookiesDir = '${dir.path}/cookies';
      final newJar = PersistCookieJar(storage: FileStorage(cookiesDir));
      // Swap cookie manager to use persistent jar
      _swapCookieJar(newJar);
      // Restore access token from secure storage
      final stored = await _secure.read(key: 'access_token');
      if (stored != null && stored.isNotEmpty) {
        _accessToken = stored;
      }
      // Restore last known /me payload if present
      try {
        final rawMe = await _secure.read(key: 'last_me');
        final rawMeAt = await _secure.read(key: 'last_me_at');
        if (rawMe != null && rawMe.isNotEmpty) {
          final decoded = jsonDecode(rawMe);
          if (decoded is Map) {
            _lastMe = Map<String, dynamic>.from(decoded);
            if (rawMeAt != null && rawMeAt.isNotEmpty) {
              _lastMeAt = DateTime.tryParse(rawMeAt);
            }
          }
        }
      } catch (_) {}
      // Apply default tenant from config
      ensureDefaultTenant();
    } catch (e) {
      // Fallback keeps memory cookie jar; app still works but won’t persist
    } finally {
      _initialized = true;
    }
  }

  void _swapCookieJar(CookieJar newJar) {
    cookieJar = newJar;
    // Remove existing CookieManager(s)
    dio.interceptors.removeWhere((i) => i is CookieManager);
    dio.interceptors.add(CookieManager(cookieJar));
  }

  Future<void> ensureFreshAccess(
      {Duration skew = const Duration(seconds: 60)}) async {
    final token = _accessToken;
    if (token == null || token.isEmpty) return;
    // Respect backoff window (e.g., after 429) and short cooldown after a recent attempt
    final now = DateTime.now();
    if (_refreshBackoffUntil != null && now.isBefore(_refreshBackoffUntil!)) {
      return; // skip refresh during backoff
    }
    if (_lastRefreshAttemptAt != null &&
        now.difference(_lastRefreshAttemptAt!) < _postRefreshCooldown) {
      return; // skip if a refresh was just attempted recently
    }
    // If there is no refresh cookie, skip refresh attempts
    if (!await _hasRefreshCookie()) return;
    try {
      final exp = JwtDecoder.getExpirationDate(token);
      if (exp.isBefore(now.add(skew))) {
        await _refreshAccess();
      }
    } catch (_) {
      // If token can't be decoded, attempt refresh once
      try {
        await _refreshAccess();
      } catch (_) {}
    }
  }

  Future<void> _refreshAccess() async {
    // Ensure only one refresh in-flight across the whole app
    if (_refreshing != null) {
      await _refreshing!.future;
      return;
    }
    _refreshing = Completer<void>();
    try {
      _lastRefreshAttemptAt = DateTime.now();
      // Cookie (HttpOnly) with refresh token is stored in cookieJar and
      // will be attached automatically to this request by CookieManager.
      try {
        // Log what we are about to send to refresh endpoint
        final refreshUri = Uri.parse('${dio.options.baseUrl}/token/refresh/');
        final cookies = await cookieJar.loadForRequest(refreshUri);
        // Extract refresh_token cookies and dedupe if needed
        final refreshCookies = cookies
            .where((c) => c.name.toLowerCase() == 'refresh_token')
            .toList();
        if (_accessToken == null && refreshCookies.isEmpty) {
          debugPrint(
              '[ApiClient] No access token and no refresh cookie. Forcing logout.');
          _forceLogout();
          throw DioException(
              requestOptions: RequestOptions(path: '/token/refresh/'),
              message: 'No credentials to refresh');
        }
        if (refreshCookies.length > 1) {
          // Choose the most recent by expires; if all null, take the last
          refreshCookies.sort((a, b) {
            final ae = a.expires;
            final be = b.expires;
            if (ae == null && be == null) return 0;
            if (ae == null) return 1;
            if (be == null) return -1;
            return be.compareTo(ae); // descending, most recent first
          });
          final winner = refreshCookies.first;
          debugPrint(
              '[ApiClient] Deduced multiple refresh_token cookies -> keeping one with path=${winner.path ?? '/'} domain=${winner.domain ?? '<default>'} expires=${winner.expires?.toIso8601String() ?? '<session>'}');
          // CookieJar doesn't delete by name; clear cookies for this URI then re-add the winner
          await cookieJar.delete(refreshUri);
          await cookieJar.saveFromResponse(refreshUri, [winner]);
        }
        // Reload to reflect any dedupe performed
        final cookiesAfter = await cookieJar.loadForRequest(refreshUri);
        if (kDebugMode) {
          final cookieDetails = cookiesAfter
              .map((c) =>
                  '${c.name}=${c.value.length > 12 ? '${c.value.substring(0, 12)}…' : c.value} (path=${c.path ?? '/'}; domain=${c.domain ?? '<default>'}; exp=${c.expires?.toIso8601String() ?? '<session>'})')
              .join('; ');
          final cookieSummary = cookiesAfter
              .map((c) =>
                  '${c.name}=${c.value.length > 12 ? '${c.value.substring(0, 12)}…' : c.value}')
              .join('; ');
          debugPrint('[ApiClient] Preparing refresh POST with headers: '
              'X-Tenant-Id=${_tenantSlug ?? '<none>'}, '
              'Authorization=${_accessToken != null ? 'Bearer ${_accessToken!.length > 12 ? '${_accessToken!.substring(0, 12)}…' : _accessToken!}' : '<none>'}');
          debugPrint(
              '[ApiClient] Cookies for /token/refresh/: ${cookiesAfter.isEmpty ? '<none>' : cookieSummary}');
          debugPrint(
              '[ApiClient] Cookie details: ${cookiesAfter.isEmpty ? '<none>' : cookieDetails}');
        }
        final res = await dio.post('/token/refresh/');
        final data = res.data as Map;
        final newAccess = data['access'] as String?;
        if (newAccess == null) {
          throw DioException(
              requestOptions: res.requestOptions,
              message: 'No access token in refresh');
        }
        debugPrint(
            '[ApiClient] Refresh succeeded; setting new access token (len=${newAccess.length})');
        setAccessToken(newAccess);
        // After a successful refresh, set a short cooldown to avoid clustered preflights
        _refreshBackoffUntil = DateTime.now().add(_postRefreshCooldown);
      } on DioException catch (e) {
        // If the refresh endpoint itself returned 401 due to invalid session/refresh
        if (e.response?.statusCode == 401) {
          debugPrint(
              '[ApiClient] Refresh 401 in preflight _refreshAccess(); triggering force logout');
          final data = e.response?.data;
          final detail = (data is Map && data['detail'] is String)
              ? data['detail'] as String
              : '';
          if (detail.contains('Session not found or inactive') ||
              detail.contains('Session has expired') ||
              detail.contains('Token is invalid or expired') ||
              detail.contains('token_not_valid') ||
              detail.contains('Refresh token not found')) {
            _forceLogout();
          }
        }
        // If server rate limited (429), back off for a few minutes to avoid hammering
        if (e.response?.statusCode == 429) {
          debugPrint('[ApiClient] Refresh 429 received; applying backoff');
          _refreshBackoffUntil = DateTime.now().add(const Duration(minutes: 5));
        }
        rethrow;
      }
    } finally {
      _refreshing!.complete();
      _refreshing = null;
    }
  }

  Future<bool> _hasRefreshCookie() async {
    try {
      final uri = Uri.parse('${dio.options.baseUrl}/token/refresh/');
      final cookies = await cookieJar.loadForRequest(uri);
      for (final c in cookies) {
        final name = c.name.toLowerCase();
        if (name.contains('refresh')) return true;
      }
    } catch (_) {}
    return false;
  }
}

class _TokenRefreshInterceptor extends Interceptor {
  final ApiClient client;

  _TokenRefreshInterceptor(this.client);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final requestOptions = err.requestOptions;
    final pathLower = requestOptions.path.toLowerCase();

    // Suppress offline message for connection-level errors
    if (err.type == DioExceptionType.connectionError ||
        err.error is SocketException) {
      return handler.next(err);
    }

    // If unauthorized and request wasn't already retried, try refresh
    final isUnauthorized = response?.statusCode == 401;
    final alreadyRetried = requestOptions.extra['retried'] == true;

    if (isUnauthorized && !alreadyRetried) {
      // If this was a logout call or server says no credentials, do not loop
      if (pathLower.contains('/logout/')) {
        return handler.reject(err);
      }
      // Do not try refresh logic on login/refresh endpoints themselves
      if (pathLower.contains('/token/refresh/') ||
          pathLower.endsWith('/token/') ||
          pathLower.contains('/token?') ||
          pathLower.contains('/token\u0026')) {
        return handler.reject(err);
      }
      final detail =
          (response?.data is Map && (response!.data)['detail'] is String)
              ? (response.data)['detail'] as String
              : '';
      if (detail.contains('Authentication credentials were not provided')) {
        // Already unauthenticated; do not force-logout again or retry
        return handler.reject(err);
      }
      // If backend explicitly signals revoked or missing refresh cookie, force logout immediately
      final data = response?.data;
      final code =
          (data is Map && data['code'] is String) ? data['code'] as String : '';
      final revoked = code == 'SESSION_REVOKED';
      // Only force logout when server explicitly says the session is revoked.
      if (revoked) {
        client._forceLogout();
        return handler.reject(err);
      }
      try {
        // If we obviously don't have a refresh cookie, don't attempt refresh
        if (!await client._hasRefreshCookie()) {
          // No way to refresh; force logout to clear bad token state
          client._forceLogout();
          return handler.reject(err);
        }
        // rely on ApiClient's global single-flight guard
        await client._refreshAccess();

        // retry the original request with flag
        final opts = Options(
          method: requestOptions.method,
          headers: Map<String, dynamic>.from(requestOptions.headers)
            ..['X-Retry'] = '1',
          extra: {...requestOptions.extra, 'retried': true},
          responseType: requestOptions.responseType,
          contentType: requestOptions.contentType,
        );

        final newResponse = await client.dio.request(
          requestOptions.path,
          data: requestOptions.data,
          queryParameters: requestOptions.queryParameters,
          options: opts,
          cancelToken: requestOptions.cancelToken,
          onReceiveProgress: requestOptions.onReceiveProgress,
          onSendProgress: requestOptions.onSendProgress,
        );
        return handler.resolve(newResponse);
      } catch (e) {
        // Refresh failed. Suppress user-facing offline notifications.
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionError ||
              e.error is SocketException) {
            // no-op: avoid SnackBar
          } else if (e.response?.statusCode == 401) {
            debugPrint(
                '[ApiClient] Interceptor: refresh failed with 401; forcing logout');
            // Any 401 from refresh means we cannot recover here. Force logout to break loops.
            if (!pathLower.contains('/logout/')) {
              client._forceLogout();
            }
          }
        }
        return handler.reject(err);
      }
    }

    return handler.next(err);
  }

  // refresh logic centralized in ApiClient._refreshAccess()
}
