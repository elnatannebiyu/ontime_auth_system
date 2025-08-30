# Part 9: Flutter HTTP Interceptors

## Overview
Implement HTTP interceptors for automatic token attachment, refresh, and error handling.

## 9.1 Base API Client

```dart
// lib/auth/api/api_client.dart
import 'package:dio/dio.dart';
import '../services/session_storage.dart';
import '../services/session_manager.dart';
import '../services/device_info_service.dart';

class ApiClient {
  static const String baseUrl = 'http://localhost:8000/api';
  static const Duration timeout = Duration(seconds: 30);
  
  late Dio _dio;
  final SessionManager _sessionManager = SessionManager();
  
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;
  
  ApiClient._internal() {
    _dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: timeout,
      receiveTimeout: timeout,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
      },
    ));
    
    // Add interceptors
    _dio.interceptors.add(AuthInterceptor());
    _dio.interceptors.add(RefreshTokenInterceptor(_dio));
    _dio.interceptors.add(ErrorInterceptor());
    _dio.interceptors.add(LoggingInterceptor());
  }
  
  Dio get dio => _dio;
  
  /// GET request
  Future<Response> get(
    String path, {
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.get(
        path,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// POST request
  Future<Response> post(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.post(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// PUT request
  Future<Response> put(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.put(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      rethrow;
    }
  }
  
  /// DELETE request
  Future<Response> delete(
    String path, {
    dynamic data,
    Map<String, dynamic>? queryParameters,
    Options? options,
  }) async {
    try {
      return await _dio.delete(
        path,
        data: data,
        queryParameters: queryParameters,
        options: options,
      );
    } catch (e) {
      rethrow;
    }
  }
}
```

## 9.2 Auth Interceptor

```dart
// lib/auth/interceptors/auth_interceptor.dart
import 'package:dio/dio.dart';
import '../services/session_storage.dart';
import '../services/device_info_service.dart';

class AuthInterceptor extends Interceptor {
  @override
  Future<void> onRequest(
    RequestOptions options,
    RequestInterceptorHandler handler,
  ) async {
    // Skip auth for public endpoints
    if (_isPublicEndpoint(options.path)) {
      return handler.next(options);
    }
    
    // Add auth token
    final token = await SessionStorage.getAccessToken();
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    // Add session ID
    final sessionId = await SessionStorage.getSessionId();
    if (sessionId != null) {
      options.headers['X-Session-ID'] = sessionId;
    }
    
    // Add device ID
    final deviceId = await SessionStorage.getDeviceId();
    options.headers['X-Device-ID'] = deviceId;
    
    // Add app version
    final appVersion = await DeviceInfoService.getAppVersion();
    options.headers['X-App-Version'] = appVersion;
    
    // Add platform
    options.headers['X-Platform'] = DeviceInfoService.getPlatform();
    
    handler.next(options);
  }
  
  bool _isPublicEndpoint(String path) {
    // Define public endpoints that don't need auth
    final publicPaths = [
      '/auth/login',
      '/auth/register',
      '/auth/forgot-password',
      '/auth/verify-otp',
      '/auth/social-login',
      '/version/check',
      '/forms/schema',
    ];
    
    return publicPaths.any((p) => path.contains(p));
  }
}
```

## 9.3 Refresh Token Interceptor

```dart
// lib/auth/interceptors/refresh_interceptor.dart
import 'package:dio/dio.dart';
import '../services/session_manager.dart';
import '../services/session_storage.dart';
import 'dart:collection';

class RefreshTokenInterceptor extends Interceptor {
  final Dio dio;
  final SessionManager _sessionManager = SessionManager();
  
  // Queue for pending requests during token refresh
  final _requestQueue = Queue<MapEntry<RequestOptions, ErrorInterceptorHandler>>();
  bool _isRefreshing = false;
  
  RefreshTokenInterceptor(this.dio);
  
  @override
  Future<void> onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) async {
    // Check if error is 401 Unauthorized
    if (err.response?.statusCode == 401) {
      final requestOptions = err.requestOptions;
      
      // Skip refresh for auth endpoints
      if (_isAuthEndpoint(requestOptions.path)) {
        return handler.next(err);
      }
      
      // Queue request if already refreshing
      if (_isRefreshing) {
        _requestQueue.add(MapEntry(requestOptions, handler));
        return;
      }
      
      _isRefreshing = true;
      
      try {
        // Attempt token refresh
        final refreshSuccess = await _sessionManager.refreshSession();
        
        if (refreshSuccess) {
          // Get new token
          final newToken = await SessionStorage.getAccessToken();
          
          // Retry original request with new token
          requestOptions.headers['Authorization'] = 'Bearer $newToken';
          
          final response = await dio.fetch(requestOptions);
          handler.resolve(response);
          
          // Process queued requests
          await _processQueuedRequests();
        } else {
          // Refresh failed, logout user
          await _sessionManager.forceLogout('Session expired');
          handler.next(err);
          
          // Reject all queued requests
          _rejectQueuedRequests(err);
        }
      } catch (e) {
        handler.next(err);
        _rejectQueuedRequests(err);
      } finally {
        _isRefreshing = false;
      }
    } else {
      handler.next(err);
    }
  }
  
  Future<void> _processQueuedRequests() async {
    final newToken = await SessionStorage.getAccessToken();
    
    while (_requestQueue.isNotEmpty) {
      final entry = _requestQueue.removeFirst();
      final options = entry.key;
      final handler = entry.value;
      
      options.headers['Authorization'] = 'Bearer $newToken';
      
      try {
        final response = await dio.fetch(options);
        handler.resolve(response);
      } catch (e) {
        handler.next(e as DioException);
      }
    }
  }
  
  void _rejectQueuedRequests(DioException error) {
    while (_requestQueue.isNotEmpty) {
      final entry = _requestQueue.removeFirst();
      entry.value.next(error);
    }
  }
  
  bool _isAuthEndpoint(String path) {
    return path.contains('/auth/refresh') || 
           path.contains('/auth/login') ||
           path.contains('/auth/logout');
  }
}
```

## 9.4 Error Interceptor

```dart
// lib/auth/interceptors/error_interceptor.dart
import 'package:dio/dio.dart';
import '../models/api_error.dart';
import '../services/session_manager.dart';

class ErrorInterceptor extends Interceptor {
  final SessionManager _sessionManager = SessionManager();
  
  @override
  void onError(
    DioException err,
    ErrorInterceptorHandler handler,
  ) {
    ApiError apiError;
    
    switch (err.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        apiError = ApiError(
          code: 'TIMEOUT',
          message: 'Connection timeout. Please try again.',
          statusCode: 0,
        );
        break;
        
      case DioExceptionType.connectionError:
        apiError = ApiError(
          code: 'NO_CONNECTION',
          message: 'No internet connection. Please check your network.',
          statusCode: 0,
        );
        break;
        
      case DioExceptionType.badResponse:
        apiError = _handleBadResponse(err);
        break;
        
      case DioExceptionType.cancel:
        apiError = ApiError(
          code: 'CANCELLED',
          message: 'Request was cancelled',
          statusCode: 0,
        );
        break;
        
      default:
        apiError = ApiError(
          code: 'UNKNOWN',
          message: 'An unexpected error occurred',
          statusCode: 0,
        );
    }
    
    // Create enhanced error
    final enhancedError = DioException(
      requestOptions: err.requestOptions,
      response: err.response,
      type: err.type,
      error: apiError,
    );
    
    handler.next(enhancedError);
  }
  
  ApiError _handleBadResponse(DioException err) {
    final statusCode = err.response?.statusCode ?? 0;
    final data = err.response?.data;
    
    // Parse error from response
    String code = 'UNKNOWN_ERROR';
    String message = 'An error occurred';
    Map<String, dynamic>? details;
    
    if (data is Map<String, dynamic>) {
      code = data['code'] ?? code;
      message = data['message'] ?? message;
      details = data['details'];
      
      // Handle specific error codes
      switch (code) {
        case 'SESSION_REVOKED':
        case 'TOKEN_REVOKED':
        case 'ACCOUNT_DISABLED':
        case 'ACCOUNT_BANNED':
          // Force logout for these errors
          _sessionManager.forceLogout(message);
          break;
          
        case 'VERSION_OUTDATED':
        case 'FORCE_UPDATE_REQUIRED':
          // Handle version update
          _handleVersionUpdate(data);
          break;
      }
    }
    
    return ApiError(
      code: code,
      message: message,
      statusCode: statusCode,
      details: details,
    );
  }
  
  void _handleVersionUpdate(Map<String, dynamic> data) {
    // Emit version update event
    // This should be handled by the app's version check service
  }
}
```

## 9.5 Logging Interceptor

```dart
// lib/auth/interceptors/logging_interceptor.dart
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

class LoggingInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    if (kDebugMode) {
      print('🚀 REQUEST[${options.method}] => PATH: ${options.path}');
      print('Headers: ${_sanitizeHeaders(options.headers)}');
      if (options.data != null) {
        print('Body: ${_sanitizeBody(options.data)}');
      }
    }
    handler.next(options);
  }
  
  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    if (kDebugMode) {
      print('✅ RESPONSE[${response.statusCode}] => PATH: ${response.requestOptions.path}');
      print('Data: ${_sanitizeBody(response.data)}');
    }
    handler.next(response);
  }
  
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (kDebugMode) {
      print('❌ ERROR[${err.response?.statusCode}] => PATH: ${err.requestOptions.path}');
      print('Message: ${err.message}');
      if (err.response?.data != null) {
        print('Error Data: ${err.response?.data}');
      }
    }
    handler.next(err);
  }
  
  Map<String, dynamic> _sanitizeHeaders(Map<String, dynamic> headers) {
    final sanitized = Map<String, dynamic>.from(headers);
    
    // Hide sensitive headers
    if (sanitized.containsKey('Authorization')) {
      sanitized['Authorization'] = 'Bearer [HIDDEN]';
    }
    if (sanitized.containsKey('X-Session-ID')) {
      sanitized['X-Session-ID'] = '[HIDDEN]';
    }
    
    return sanitized;
  }
  
  dynamic _sanitizeBody(dynamic body) {
    if (body is Map<String, dynamic>) {
      final sanitized = Map<String, dynamic>.from(body);
      
      // Hide sensitive fields
      final sensitiveFields = ['password', 'token', 'refresh_token', 'access_token'];
      for (final field in sensitiveFields) {
        if (sanitized.containsKey(field)) {
          sanitized[field] = '[HIDDEN]';
        }
      }
      
      return sanitized;
    }
    return body;
  }
}
```

## 9.6 API Error Model

```dart
// lib/auth/models/api_error.dart
class ApiError {
  final String code;
  final String message;
  final int statusCode;
  final Map<String, dynamic>? details;
  
  ApiError({
    required this.code,
    required this.message,
    required this.statusCode,
    this.details,
  });
  
  factory ApiError.fromJson(Map<String, dynamic> json) {
    return ApiError(
      code: json['code'] ?? 'UNKNOWN',
      message: json['message'] ?? 'An error occurred',
      statusCode: json['status_code'] ?? 0,
      details: json['details'],
    );
  }
  
  bool get isNetworkError => statusCode == 0;
  bool get isServerError => statusCode >= 500;
  bool get isClientError => statusCode >= 400 && statusCode < 500;
  bool get isAuthError => statusCode == 401 || statusCode == 403;
  
  @override
  String toString() => 'ApiError: [$code] $message';
}
```

## 9.7 API Response Wrapper

```dart
// lib/auth/models/api_response.dart
class ApiResponse<T> {
  final bool success;
  final T? data;
  final ApiError? error;
  final Map<String, dynamic>? metadata;
  
  ApiResponse({
    required this.success,
    this.data,
    this.error,
    this.metadata,
  });
  
  factory ApiResponse.success(T data, {Map<String, dynamic>? metadata}) {
    return ApiResponse(
      success: true,
      data: data,
      metadata: metadata,
    );
  }
  
  factory ApiResponse.error(ApiError error) {
    return ApiResponse(
      success: false,
      error: error,
    );
  }
}
```

## 9.8 Usage Example

```dart
// lib/auth/api/auth_api.dart
import 'package:dio/dio.dart';
import '../models/api_response.dart';
import '../models/api_error.dart';
import 'api_client.dart';

class AuthApi {
  static final ApiClient _client = ApiClient();
  
  /// Login with email and password
  static Future<ApiResponse<Map<String, dynamic>>> login({
    required String email,
    required String password,
  }) async {
    try {
      final response = await _client.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
        },
      );
      
      return ApiResponse.success(response.data);
    } on DioException catch (e) {
      return ApiResponse.error(e.error as ApiError);
    }
  }
  
  /// Refresh token
  static Future<ApiResponse<Map<String, dynamic>>> refreshToken({
    required String refreshToken,
    required String deviceId,
  }) async {
    try {
      final response = await _client.post(
        '/auth/refresh',
        data: {
          'refresh': refreshToken,
          'device_id': deviceId,
        },
      );
      
      return ApiResponse.success(response.data);
    } on DioException catch (e) {
      return ApiResponse.error(e.error as ApiError);
    }
  }
  
  /// Logout
  static Future<ApiResponse<void>> logout({
    required String sessionId,
  }) async {
    try {
      await _client.post(
        '/auth/logout',
        data: {
          'session_id': sessionId,
        },
      );
      
      return ApiResponse.success(null);
    } on DioException catch (e) {
      return ApiResponse.error(e.error as ApiError);
    }
  }
}
```

## Testing

```dart
// test/interceptor_test.dart
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:your_app/auth/api/api_client.dart';

void main() {
  test('Auth interceptor adds token', () async {
    // Mock session storage
    // Test that requests include auth token
  });
  
  test('Refresh interceptor handles 401', () async {
    // Mock 401 response
    // Verify token refresh is attempted
    // Verify request is retried with new token
  });
  
  test('Error interceptor handles network errors', () async {
    // Simulate network error
    // Verify proper error handling
  });
}
```

## Dependencies

Add to `pubspec.yaml`:
```yaml
dependencies:
  dio: ^5.0.0
```

## Security Notes

1. **Token Security**: Never log tokens in production
2. **Request Queue**: Prevent multiple simultaneous refresh attempts
3. **Error Handling**: Graceful degradation on network errors
4. **Session Validation**: Verify session on each request
5. **Certificate Pinning**: Consider adding for production

## Next Steps

✅ Base API client with Dio
✅ Auth interceptor for token attachment
✅ Refresh token interceptor
✅ Error handling interceptor
✅ Logging interceptor for debugging

Continue to [Part 10: Flutter Dynamic Forms](./part10-flutter-forms.md)
