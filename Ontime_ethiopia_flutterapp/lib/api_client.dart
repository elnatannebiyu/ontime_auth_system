// ignore_for_file: unused_element

import 'dart:async';
import 'dart:io' show SocketException, Platform;
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path_provider/path_provider.dart';
import 'package:jwt_decoder/jwt_decoder.dart';
import 'auth/services/device_info_service.dart';

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
  Completer<void>? _refreshing; // single-flight guard for refresh

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
        )),
        cookieJar = CookieJar() {
    dio.interceptors.add(CookieManager(cookieJar));

    // Dev logging: print requests/responses/errors to console
    if (kDebugMode) {
      dio.interceptors.add(LogInterceptor(
        request: true,
        requestBody: true,
        requestHeader: false,
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
        final isAuthEndpoint =
            lower.contains('/token/refresh/') || lower.contains('/token/');
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

  /// Allows changing the base URL at runtime (e.g., user setting or detection)
  void setBaseUrl(String base) {
    if (base.isEmpty) return;
    if (!base.startsWith('http')) return;
    dio.options.baseUrl = base.endsWith('/api') ? base : "$base/api";
    kApiBase = base; // keep global in sync for diagnostics
  }

  String? get tenant => _tenantSlug;

  /// Register a callback invoked when we must force logout (e.g., missing refresh cookie or session revoked)
  void setForceLogoutHandler(void Function()? handler) {
    _onForceLogout = handler;
  }

  /// Register a lightweight notifier to surface user messages (e.g., offline snackbar)
  void setNotifier(void Function(String message)? handler) {
    _onNotify = handler;
  }

  void _forceLogout() async {
    debugPrint('[ApiClient] Forcing logout: clearing access token and cookies');
    _accessToken = null;
    try {
      await cookieJar.deleteAll();
      await _secure.delete(key: 'access_token');
    } catch (_) {}
    final cb = _onForceLogout;
    if (cb != null) {
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
    // If there is no refresh cookie, skip refresh attempts
    if (!await _hasRefreshCookie()) return;
    try {
      final exp = JwtDecoder.getExpirationDate(token);
      final now = DateTime.now();
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

    // Suppress offline message for connection-level errors
    if (err.type == DioExceptionType.connectionError ||
        err.error is SocketException) {
      return handler.next(err);
    }

    // If unauthorized and request wasn't already retried, try refresh
    final isUnauthorized = response?.statusCode == 401;
    final alreadyRetried = requestOptions.extra['retried'] == true;

    if (isUnauthorized && !alreadyRetried) {
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
            client._forceLogout();
          }
        }
        return handler.reject(err);
      }
    }

    return handler.next(err);
  }

  // refresh logic centralized in ApiClient._refreshAccess()
}
