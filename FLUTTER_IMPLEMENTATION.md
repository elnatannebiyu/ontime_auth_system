# Flutter Implementation Guide

## Overview
Complete Flutter implementation for authentication with version gate, dynamic forms, and social sign-in.

---

## Part 1: Core Services

### 1.1 Version Service
```dart
// lib/core/services/version_service.dart
import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io' show Platform;

class VersionCheckResult {
  final bool updateRequired;
  final bool updateAvailable;
  final String? storeUrl;
  final String? minVersion;
  final String? latestVersion;
  final String? notes;
  
  VersionCheckResult({
    required this.updateRequired,
    required this.updateAvailable,
    this.storeUrl,
    this.minVersion,
    this.latestVersion,
    this.notes,
  });
}

class VersionService {
  final Dio _dio;
  static const cacheTimeout = Duration(minutes: 5);
  DateTime? _lastCheck;
  Map<String, dynamic>? _cachedResponse;
  
  VersionService(this._dio);
  
  Future<VersionCheckResult> checkVersion({bool force = false}) async {
    // Use cache if valid
    if (!force && _lastCheck != null && _cachedResponse != null) {
      final elapsed = DateTime.now().difference(_lastCheck!);
      if (elapsed < cacheTimeout) {
        return _parseResponse(_cachedResponse!);
      }
    }
    
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final platform = Platform.isIOS ? 'ios' : 'android';
      
      final response = await _dio.get(
        '/app/version',
        queryParameters: {'platform': platform},
        options: Options(
          headers: {
            'X-App-Version': packageInfo.version,
            'X-App-Platform': platform,
          },
        ),
      );
      
      _cachedResponse = response.data;
      _lastCheck = DateTime.now();
      
      return _parseResponse(response.data);
    } catch (e) {
      // Fail open - allow app to continue
      return VersionCheckResult(
        updateRequired: false,
        updateAvailable: false,
      );
    }
  }
  
  VersionCheckResult _parseResponse(Map<String, dynamic> data) {
    final PackageInfo packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = packageInfo.version;
    final minSupported = data['min_supported'] ?? '0.0.0';
    final latest = data['latest'] ?? '0.0.0';
    
    return VersionCheckResult(
      updateRequired: _compareVersions(currentVersion, minSupported) < 0,
      updateAvailable: _compareVersions(currentVersion, latest) < 0,
      storeUrl: data['store_url'],
      minVersion: minSupported,
      latestVersion: latest,
      notes: data['notes'],
    );
  }
  
  int _compareVersions(String v1, String v2) {
    final parts1 = v1.split('.').map(int.parse).toList();
    final parts2 = v2.split('.').map(int.parse).toList();
    
    for (int i = 0; i < 3; i++) {
      final p1 = i < parts1.length ? parts1[i] : 0;
      final p2 = i < parts2.length ? parts2[i] : 0;
      if (p1 < p2) return -1;
      if (p1 > p2) return 1;
    }
    return 0;
  }
  
  Future<void> openStore(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
```

### 1.2 Enhanced Auth Service
```dart
// lib/core/services/auth_service.dart
import 'package:dio/dio.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io' show Platform;

class AuthService {
  final Dio _dio;
  final GoogleSignIn _googleSignIn = GoogleSignIn(
    scopes: ['email', 'profile'],
  );
  
  String? _accessToken;
  String? _refreshToken;
  
  AuthService(this._dio);
  
  // Email/Password Login
  Future<AuthResult> login({
    required String email,
    required String password,
    required String tenantId,
  }) async {
    try {
      final response = await _dio.post(
        '/api/v1/auth/login',
        data: {
          'email': email,
          'password': password,
        },
        options: Options(
          headers: {'X-Tenant-ID': tenantId},
        ),
      );
      
      return _handleAuthResponse(response.data);
    } on DioException catch (e) {
      throw _handleError(e);
    }
  }
  
  // Phone OTP Login
  Future<void> sendOTP(String phoneNumber) async {
    await _dio.post(
      '/api/v1/auth/otp/send',
      data: {
        'destination': phoneNumber,
        'type': 'phone',
      },
    );
  }
  
  Future<AuthResult> verifyOTP({
    required String phoneNumber,
    required String code,
  }) async {
    final response = await _dio.post(
      '/api/v1/auth/otp/verify',
      data: {
        'destination': phoneNumber,
        'code': code,
      },
    );
    
    return _handleAuthResponse(response.data);
  }
  
  // Google Sign-In
  Future<AuthResult> signInWithGoogle() async {
    try {
      final account = await _googleSignIn.signIn();
      if (account == null) throw Exception('Sign-in cancelled');
      
      final auth = await account.authentication;
      
      final response = await _dio.post(
        '/api/v1/auth/google',
        data: {
          'id_token': auth.idToken,
        },
      );
      
      return _handleAuthResponse(response.data);
    } catch (e) {
      throw Exception('Google sign-in failed: $e');
    }
  }
  
  // Apple Sign-In
  Future<AuthResult> signInWithApple() async {
    if (!Platform.isIOS) {
      throw Exception('Apple sign-in only available on iOS');
    }
    
    try {
      final credential = await SignInWithApple.getAppleIDCredential(
        scopes: [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
      );
      
      final response = await _dio.post(
        '/api/v1/auth/apple',
        data: {
          'identity_token': credential.identityToken,
          'authorization_code': credential.authorizationCode,
        },
      );
      
      return _handleAuthResponse(response.data);
    } catch (e) {
      throw Exception('Apple sign-in failed: $e');
    }
  }
  
  // Registration
  Future<AuthResult> register({
    required Map<String, dynamic> formData,
    required String tenantId,
  }) async {
    final response = await _dio.post(
      '/api/v1/auth/register',
      data: {
        ...formData,
        'platform': Platform.isIOS ? 'ios' : 'android',
        'app_version': await _getAppVersion(),
      },
      options: Options(
        headers: {'X-Tenant-ID': tenantId},
      ),
    );
    
    return _handleAuthResponse(response.data);
  }
  
  // Token Management
  AuthResult _handleAuthResponse(Map<String, dynamic> data) {
    _accessToken = data['access_token'] ?? data['access'];
    _refreshToken = data['refresh_token'] ?? data['refresh'];
    
    _saveTokens();
    _dio.options.headers['Authorization'] = 'Bearer $_accessToken';
    
    return AuthResult(
      accessToken: _accessToken!,
      refreshToken: _refreshToken,
      userCreated: data['user_created'] ?? false,
      profile: data['profile'],
    );
  }
  
  Future<void> _saveTokens() async {
    final prefs = await SharedPreferences.getInstance();
    if (_accessToken != null) {
      await prefs.setString('access_token', _accessToken!);
    }
    if (_refreshToken != null) {
      await prefs.setString('refresh_token', _refreshToken!);
    }
  }
  
  Future<String> _getAppVersion() async {
    final packageInfo = await PackageInfo.fromPlatform();
    return packageInfo.version;
  }
  
  Exception _handleError(DioException e) {
    if (e.response?.statusCode == 426) {
      return Exception('APP_UPDATE_REQUIRED');
    }
    return Exception(e.response?.data['error'] ?? 'Auth failed');
  }
}

class AuthResult {
  final String accessToken;
  final String? refreshToken;
  final bool userCreated;
  final Map<String, dynamic>? profile;
  
  AuthResult({
    required this.accessToken,
    this.refreshToken,
    required this.userCreated,
    this.profile,
  });
}
```

### 1.3 Dynamic Form Service
```dart
// lib/core/services/form_service.dart
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

class FormService {
  final Dio _dio;
  Map<String, FormSchema> _cache = {};
  
  FormService(this._dio);
  
  Future<FormSchema> getFormSchema(String formName) async {
    // Check cache
    if (_cache.containsKey(formName)) {
      return _cache[formName]!;
    }
    
    final response = await _dio.get(
      '/api/v1/auth/forms',
      queryParameters: {
        'name': formName,
        'locale': 'en-US',
        'country': 'US',
      },
    );
    
    final schema = FormSchema.fromJson(response.data);
    _cache[formName] = schema;
    
    return schema;
  }
  
  void clearCache() {
    _cache.clear();
  }
}

class FormSchema {
  final String version;
  final String name;
  final String action;
  final List<FormField> fields;
  final List<FormAction> actions;
  final Map<String, dynamic>? meta;
  
  FormSchema({
    required this.version,
    required this.name,
    required this.action,
    required this.fields,
    required this.actions,
    this.meta,
  });
  
  factory FormSchema.fromJson(Map<String, dynamic> json) {
    return FormSchema(
      version: json['schema_version'],
      name: json['form']['name'],
      action: json['form']['action'],
      fields: (json['fields'] as List)
          .map((f) => FormField.fromJson(f))
          .toList(),
      actions: (json['actions'] as List)
          .map((a) => FormAction.fromJson(a))
          .toList(),
      meta: json['meta'],
    );
  }
}

class FormField {
  final String name;
  final String type;
  final String label;
  final String? placeholder;
  final bool required;
  final Map<String, dynamic>? validators;
  final Map<String, dynamic>? visibleIf;
  
  FormField({
    required this.name,
    required this.type,
    required this.label,
    this.placeholder,
    required this.required,
    this.validators,
    this.visibleIf,
  });
  
  factory FormField.fromJson(Map<String, dynamic> json) {
    return FormField(
      name: json['name'],
      type: json['type'],
      label: json['label'],
      placeholder: json['placeholder'],
      required: json['required'] ?? false,
      validators: json['validators'],
      visibleIf: json['visible_if'],
    );
  }
}

class FormAction {
  final String id;
  final String type;
  final String? label;
  final String? provider;
  final bool? primary;
  
  FormAction({
    required this.id,
    required this.type,
    this.label,
    this.provider,
    this.primary,
  });
  
  factory FormAction.fromJson(Map<String, dynamic> json) {
    return FormAction(
      id: json['id'],
      type: json['type'],
      label: json['label'],
      provider: json['provider'],
      primary: json['primary'],
    );
  }
}
```

---

## Part 2: Dynamic Form Rendering

### 2.1 Form Builder Widget
```dart
// lib/core/widgets/dynamic_form_builder.dart
import 'package:flutter/material.dart';
import 'package:reactive_forms/reactive_forms.dart';
import '../services/form_service.dart';

class DynamicFormBuilder extends StatefulWidget {
  final FormSchema schema;
  final Function(Map<String, dynamic>) onSubmit;
  
  const DynamicFormBuilder({
    Key? key,
    required this.schema,
    required this.onSubmit,
  }) : super(key: key);
  
  @override
  State<DynamicFormBuilder> createState() => _DynamicFormBuilderState();
}

class _DynamicFormBuilderState extends State<DynamicFormBuilder> {
  late FormGroup form;
  
  @override
  void initState() {
    super.initState();
    form = _buildFormGroup();
  }
  
  FormGroup _buildFormGroup() {
    final controls = <String, AbstractControl>{};
    
    for (final field in widget.schema.fields) {
      final validators = _buildValidators(field);
      controls[field.name] = FormControl(
        validators: validators,
      );
    }
    
    return FormGroup(controls);
  }
  
  List<Validator> _buildValidators(FormField field) {
    final validators = <Validator>[];
    
    if (field.required) {
      validators.add(Validators.required);
    }
    
    if (field.type == 'email') {
      validators.add(Validators.email);
    }
    
    if (field.validators != null) {
      final minLength = field.validators!['min_length'];
      if (minLength != null) {
        validators.add(Validators.minLength(minLength));
      }
    }
    
    return validators;
  }
  
  @override
  Widget build(BuildContext context) {
    return ReactiveForm(
      formGroup: form,
      child: Column(
        children: [
          ...widget.schema.fields.map(_buildField),
          const SizedBox(height: 24),
          ...widget.schema.actions
              .where((a) => a.type == 'submit')
              .map(_buildSubmitButton),
        ],
      ),
    );
  }
  
  Widget _buildField(FormField field) {
    switch (field.type) {
      case 'email':
        return _buildTextField(field, TextInputType.emailAddress);
      case 'password':
        return _buildPasswordField(field);
      case 'phone':
        return _buildPhoneField(field);
      case 'checkbox':
        return _buildCheckbox(field);
      default:
        return _buildTextField(field, TextInputType.text);
    }
  }
  
  Widget _buildTextField(FormField field, TextInputType keyboardType) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ReactiveTextField(
        formControlName: field.name,
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        keyboardType: keyboardType,
      ),
    );
  }
  
  Widget _buildPasswordField(FormField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ReactiveTextField(
        formControlName: field.name,
        obscureText: true,
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
  
  Widget _buildPhoneField(FormField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ReactiveTextField(
        formControlName: field.name,
        decoration: InputDecoration(
          labelText: field.label,
          hintText: field.placeholder ?? '+1234567890',
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        keyboardType: TextInputType.phone,
      ),
    );
  }
  
  Widget _buildCheckbox(FormField field) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: ReactiveCheckboxListTile(
        formControlName: field.name,
        title: Text(field.label),
      ),
    );
  }
  
  Widget _buildSubmitButton(FormAction action) {
    return SizedBox(
      width: double.infinity,
      height: 48,
      child: ReactiveFormConsumer(
        builder: (context, form, child) {
          return ElevatedButton(
            onPressed: form.valid
                ? () => widget.onSubmit(form.value)
                : null,
            style: ElevatedButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text(action.label ?? 'Submit'),
          );
        },
      ),
    );
  }
}
```

---

## Part 3: Version Gate UI

### 3.1 Update Dialog
```dart
// lib/core/widgets/update_dialog.dart
import 'package:flutter/material.dart';
import '../services/version_service.dart';

class UpdateDialog extends StatelessWidget {
  final VersionCheckResult result;
  final VoidCallback onUpdate;
  final VoidCallback? onSkip;
  
  const UpdateDialog({
    Key? key,
    required this.result,
    required this.onUpdate,
    this.onSkip,
  }) : super(key: key);
  
  @override
  Widget build(BuildContext context) {
    final isForced = result.updateRequired;
    
    return AlertDialog(
      title: Text(isForced ? 'Update Required' : 'Update Available'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isForced
                ? 'You must update to continue using the app.'
                : 'A new version is available with improvements.',
          ),
          if (result.notes != null) ...[
            const SizedBox(height: 16),
            Text(
              result.notes!,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 16),
          Text(
            'Version ${result.latestVersion}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ],
      ),
      actions: [
        if (!isForced && onSkip != null)
          TextButton(
            onPressed: onSkip,
            child: const Text('Later'),
          ),
        ElevatedButton(
          onPressed: onUpdate,
          child: const Text('Update Now'),
        ),
      ],
    );
  }
}
```

### 3.2 App Wrapper with Version Check
```dart
// lib/core/app_wrapper.dart
import 'package:flutter/material.dart';
import 'services/version_service.dart';
import 'widgets/update_dialog.dart';

class AppWrapper extends StatefulWidget {
  final Widget child;
  final VersionService versionService;
  
  const AppWrapper({
    Key? key,
    required this.child,
    required this.versionService,
  }) : super(key: key);
  
  @override
  State<AppWrapper> createState() => _AppWrapperState();
}

class _AppWrapperState extends State<AppWrapper> with WidgetsBindingObserver {
  bool _checking = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkVersion();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkVersion();
    }
  }
  
  Future<void> _checkVersion() async {
    if (_checking) return;
    _checking = true;
    
    try {
      final result = await widget.versionService.checkVersion();
      
      if (!mounted) return;
      
      if (result.updateRequired || result.updateAvailable) {
        showDialog(
          context: context,
          barrierDismissible: !result.updateRequired,
          builder: (_) => UpdateDialog(
            result: result,
            onUpdate: () => _openStore(result.storeUrl),
            onSkip: result.updateRequired ? null : Navigator.of(context).pop,
          ),
        );
      }
    } finally {
      _checking = false;
    }
  }
  
  void _openStore(String? url) {
    if (url != null) {
      widget.versionService.openStore(url);
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
```

---

## Part 4: Enhanced Auth Pages

### 4.1 Dynamic Login Page
```dart
// lib/auth/dynamic_login_page.dart
import 'package:flutter/material.dart';
import '../core/services/form_service.dart';
import '../core/services/auth_service.dart';
import '../core/widgets/dynamic_form_builder.dart';

class DynamicLoginPage extends StatefulWidget {
  @override
  State<DynamicLoginPage> createState() => _DynamicLoginPageState();
}

class _DynamicLoginPageState extends State<DynamicLoginPage> {
  final FormService _formService = FormService(dio);
  final AuthService _authService = AuthService(dio);
  
  FormSchema? _schema;
  bool _loading = true;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _loadFormSchema();
  }
  
  Future<void> _loadFormSchema() async {
    try {
      final schema = await _formService.getFormSchema('login');
      setState(() {
        _schema = schema;
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  Future<void> _handleSubmit(Map<String, dynamic> data) async {
    try {
      setState(() => _loading = true);
      
      final result = await _authService.login(
        email: data['email'],
        password: data['password'],
        tenantId: 'default',
      );
      
      // Navigate to home
      Navigator.pushReplacementNamed(context, '/home');
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 400),
          padding: const EdgeInsets.all(24),
          child: _buildContent(),
        ),
      ),
    );
  }
  
  Widget _buildContent() {
    if (_loading) {
      return const CircularProgressIndicator();
    }
    
    if (_error != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Error: $_error'),
          ElevatedButton(
            onPressed: _loadFormSchema,
            child: const Text('Retry'),
          ),
        ],
      );
    }
    
    if (_schema == null) {
      return const Text('No form schema available');
    }
    
    return DynamicFormBuilder(
      schema: _schema!,
      onSubmit: _handleSubmit,
    );
  }
}
```

---

## Part 5: Main App Integration

### 5.1 App Configuration
```dart
// lib/main.dart
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'core/app_wrapper.dart';
import 'core/services/version_service.dart';
import 'core/interceptors/auth_interceptor.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  final dio = Dio(BaseOptions(
    baseUrl: 'https://api.example.com',
    connectTimeout: const Duration(seconds: 10),
    receiveTimeout: const Duration(seconds: 10),
  ));
  
  @override
  Widget build(BuildContext context) {
    // Add interceptors
    dio.interceptors.add(AuthInterceptor());
    dio.interceptors.add(VersionInterceptor());
    
    final versionService = VersionService(dio);
    
    return MaterialApp(
      title: 'OnTime Auth',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: AppWrapper(
        versionService: versionService,
        child: AuthNavigator(),
      ),
    );
  }
}
```

### 5.2 Auth Interceptor
```dart
// lib/core/interceptors/auth_interceptor.dart
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuthInterceptor extends Interceptor {
  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('access_token');
    
    if (token != null) {
      options.headers['Authorization'] = 'Bearer $token';
    }
    
    handler.next(options);
  }
  
  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    if (err.response?.statusCode == 401) {
      // Handle token refresh or logout
    } else if (err.response?.statusCode == 426) {
      // Handle version gate
      final data = err.response?.data;
      throw Exception('Update required: ${data['min_supported']}');
    }
    
    handler.next(err);
  }
}
```

---

## Testing

### Unit Tests
```dart
// test/version_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';

void main() {
  group('VersionService', () {
    test('compares versions correctly', () {
      final service = VersionService(MockDio());
      
      expect(service.compareVersions('1.2.3', '1.2.4'), -1);
      expect(service.compareVersions('1.3.0', '1.2.4'), 1);
      expect(service.compareVersions('1.2.3', '1.2.3'), 0);
    });
    
    test('caches version response', () async {
      // Test cache behavior
    });
  });
}
```

### Widget Tests
```dart
// test/form_builder_test.dart
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('DynamicFormBuilder renders fields', (tester) async {
    final schema = FormSchema(
      version: '1.0',
      name: 'test',
      action: '/test',
      fields: [
        FormField(
          name: 'email',
          type: 'email',
          label: 'Email',
          required: true,
        ),
      ],
      actions: [],
    );
    
    await tester.pumpWidget(
      MaterialApp(
        home: DynamicFormBuilder(
          schema: schema,
          onSubmit: (_) {},
        ),
      ),
    );
    
    expect(find.text('Email'), findsOneWidget);
  });
}
```

---

## Usage Example

```dart
// Example: Complete auth flow with all features
class AuthFlow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return AppWrapper(
      versionService: VersionService(dio),
      child: Navigator(
        initialRoute: '/splash',
        onGenerateRoute: (settings) {
          switch (settings.name) {
            case '/splash':
              return MaterialPageRoute(
                builder: (_) => SplashScreen(),
              );
            case '/login':
              return MaterialPageRoute(
                builder: (_) => DynamicLoginPage(),
              );
            case '/register':
              return MaterialPageRoute(
                builder: (_) => DynamicRegisterPage(),
              );
            case '/home':
              return MaterialPageRoute(
                builder: (_) => HomePage(),
              );
            default:
              return null;
          }
        },
      ),
    );
  }
}
```

---

## Security Notes

1. **Token Storage**: Use `flutter_secure_storage` for production
2. **Certificate Pinning**: Implement for API calls
3. **Biometric Auth**: Add for sensitive operations
4. **Obfuscation**: Enable for release builds
5. **ProGuard/R8**: Configure for Android

---

## Next Steps

1. Add comprehensive error handling
2. Implement offline support with cache
3. Add analytics tracking
4. Implement deep linking
5. Add push notifications
6. Add localization
7. Add widget and integration tests
