import 'dart:async';
import 'dart:io' show SocketException, Platform;
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';
import 'package:flutter/foundation.dart';
import 'auth/services/device_info_service.dart';

/// Configure backend origin per platform with environment overrides
/// Priority:
/// 1) Dart-define LAN_API_BASE (e.g., http://192.168.1.50:8000)
/// 2) ANDROID_NET_MODE (emulator | device_local | auto)
/// 3) Platform defaults
const String _envLanBase = String.fromEnvironment('LAN_API_BASE', defaultValue: '');
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
        // Prefer device-local for physical phone (Termux), else fallback can be adjusted at runtime
        return 'http://127.0.0.1:8000';
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
  final CookieJar cookieJar;
  String? _accessToken; // keep in memory; don't persist unless you must
  String? _tenantSlug; // e.g., "default", sent via X-Tenant-Id
  void Function()? _onForceLogout; // optional app-level handler
  void Function(String message)? _onNotify; // optional UI notifier (e.g., snackbar)

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
    _accessToken = null;
    try {
      await cookieJar.deleteAll();
    } catch (_) {}
    final cb = _onForceLogout;
    if (cb != null) cb();
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
}

class _TokenRefreshInterceptor extends Interceptor {
  final ApiClient client;
  Completer<void>? _refreshing;

  _TokenRefreshInterceptor(this.client);

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    final response = err.response;
    final requestOptions = err.requestOptions;

    // Surface offline message for connection-level errors
    if (err.type == DioExceptionType.connectionError || err.error is SocketException) {
      client._notify('You appear to be offline. Some actions may not work.');
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
        // ensure single refresh in-flight
        if (_refreshing == null) {
          _refreshing = Completer<void>();
          await _refreshAccess();
          _refreshing!.complete();
          _refreshing = null;
        } else {
          await _refreshing!.future;
        }

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
        // Refresh failed. If likely offline or missing refresh, notify user instead of forcing logout.
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionError || e.error is SocketException) {
            client._notify('You appear to be offline. Please reconnect and try again.');
          } else if (e.response?.statusCode == 401) {
            final data = e.response?.data;
            final detail = (data is Map && data['detail'] is String) ? data['detail'] as String : '';
            if (detail.contains('Refresh token not found')) {
              client._notify('You appear to be offline. Please reconnect and try again.');
            }
          }
        }
        return handler.reject(err);
      }
    }

    return handler.next(err);
  }

  Future<void> _refreshAccess() async {
    // Cookie (HttpOnly) with refresh token is stored in cookieJar and
    // will be attached automatically to this request.
    final res = await client.dio.post('/token/refresh/');
    final data = res.data as Map;
    final newAccess = data['access'] as String?;
    if (newAccess == null) {
      throw DioException(
          requestOptions: res.requestOptions,
          message: 'No access token in refresh');
    }
    client.setAccessToken(newAccess);
  }
}
