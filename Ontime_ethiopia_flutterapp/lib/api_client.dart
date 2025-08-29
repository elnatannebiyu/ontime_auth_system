import 'dart:async';
import 'package:dio/dio.dart';
import 'package:cookie_jar/cookie_jar.dart';
import 'package:dio_cookie_manager/dio_cookie_manager.dart';

/// Configure this to your backend origin
// const String kApiBase = "http://10.0.2.2:8000"; // Android emulator -> host
const String kApiBase = "http://localhost:8000"; // iOS simulator / desktop / web
// const String kApiBase = "https://api.yourdomain.com"; // production (HTTPS)

class ApiClient {
  final Dio dio;
  final CookieJar cookieJar;
  String? _accessToken; // keep in memory; don't persist unless you must
  String? _tenantSlug;  // e.g., "default", sent via X-Tenant-Id

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

    // Attach Authorization header if we have an access token
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) {
      if (_accessToken != null) {
        options.headers['Authorization'] = 'Bearer $_accessToken';
      }
      if (_tenantSlug != null && _tenantSlug!.isNotEmpty) {
        options.headers['X-Tenant-Id'] = _tenantSlug;
      }
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

  String? get tenant => _tenantSlug;

  Future<Response<T>> post<T>(String path, {data, Options? options}) {
    return dio.post<T>(path, data: data, options: options);
  }

  Future<Response<T>> get<T>(String path, {Map<String, dynamic>? queryParameters, Options? options}) {
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

    // If unauthorized and request wasn't already retried, try refresh
    final isUnauthorized = response?.statusCode == 401;
    final alreadyRetried = requestOptions.extra['retried'] == true;

    if (isUnauthorized && !alreadyRetried) {
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
          headers: Map<String, dynamic>.from(requestOptions.headers)..['X-Retry'] = '1',
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
        // refresh failed -> clear token, bubble up 401
        client.setAccessToken(null);
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
      throw DioException(requestOptions: res.requestOptions, message: 'No access token in refresh');
    }
    client.setAccessToken(newAccess);
  }
}
