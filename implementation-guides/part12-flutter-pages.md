# Part 12: Flutter Auth Pages

## Overview

This guide implements the complete authentication UI pages in Flutter, integrating all previous components (session management, interceptors, dynamic forms, version gate).

## 12.1 Login Page

```dart
// lib/auth/pages/login_page.dart
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../widgets/dynamic_form.dart';
import '../services/form_service.dart';
import '../models/form_schema_model.dart';
import '../../core/managers/session_manager.dart';

class LoginPage extends StatefulWidget {
  final VoidCallback? onSuccess;
  
  const LoginPage({Key? key, this.onSuccess}) : super(key: key);
  
  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  FormSchemaModel? _formSchema;
  bool _isLoading = true;
  bool _isSubmitting = false;
  String? _error;
  
  @override
  void initState() {
    super.initState();
    _loadFormSchema();
  }
  
  Future<void> _loadFormSchema() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    
    final response = await FormService.getFormSchema('login');
    
    setState(() {
      _isLoading = false;
      if (response.success) {
        _formSchema = response.data;
      } else {
        _error = response.error?.message;
      }
    });
  }
  
  Future<void> _handleLogin(Map<String, dynamic> formData) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    
    final response = await AuthService.login(
      email: formData['email'],
      password: formData['password'],
      rememberMe: formData['remember_me'] ?? false,
    );
    
    setState(() {
      _isSubmitting = false;
    });
    
    if (response.success) {
      // Update session
      final sessionManager = context.read<SessionManager>();
      await sessionManager.createSession(response.data!);
      
      // Navigate to home
      if (widget.onSuccess != null) {
        widget.onSuccess!();
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      setState(() {
        _error = response.error?.message;
      });
    }
  }
  
  void _navigateToRegister() {
    Navigator.of(context).pushNamed('/register');
  }
  
  void _navigateToForgotPassword() {
    Navigator.of(context).pushNamed('/forgot-password');
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: 400),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _buildLogo(),
                  SizedBox(height: 48),
                  _buildTitle(),
                  SizedBox(height: 32),
                  _buildContent(),
                  SizedBox(height: 24),
                  _buildSocialAuth(),
                  SizedBox(height: 16),
                  _buildFooter(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
  
  Widget _buildLogo() {
    return Image.asset(
      'assets/images/logo.png',
      height: 80,
      width: 80,
    );
  }
  
  Widget _buildTitle() {
    return Column(
      children: [
        Text(
          'Welcome Back',
          style: Theme.of(context).textTheme.headlineMedium,
        ),
        SizedBox(height: 8),
        Text(
          'Sign in to continue',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.grey[600],
              ),
        ),
      ],
    );
  }
  
  Widget _buildContent() {
    if (_isLoading) {
      return Center(child: CircularProgressIndicator());
    }
    
    if (_error != null && _formSchema == null) {
      return Column(
        children: [
          Icon(Icons.error_outline, size: 64, color: Colors.red),
          SizedBox(height: 16),
          Text(_error!),
          SizedBox(height: 16),
          ElevatedButton(
            onPressed: _loadFormSchema,
            child: Text('Retry'),
          ),
        ],
      );
    }
    
    if (_formSchema == null) {
      // Fallback to static form
      return _buildStaticLoginForm();
    }
    
    return Column(
      children: [
        if (_error != null)
          Container(
            padding: EdgeInsets.all(12),
            margin: EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.shade50,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 12),
                Expanded(child: Text(_error!)),
              ],
            ),
          ),
        
        DynamicForm(
          schema: _formSchema!,
          onSubmit: _handleLogin,
          isLoading: _isSubmitting,
        ),
        
        SizedBox(height: 16),
        
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: _navigateToForgotPassword,
            child: Text('Forgot Password?'),
          ),
        ),
      ],
    );
  }
  
  Widget _buildStaticLoginForm() {
    final emailController = TextEditingController();
    final passwordController = TextEditingController();
    bool rememberMe = false;
    
    return Column(
      children: [
        TextField(
          controller: emailController,
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(Icons.email),
          ),
          keyboardType: TextInputType.emailAddress,
        ),
        SizedBox(height: 16),
        TextField(
          controller: passwordController,
          decoration: InputDecoration(
            labelText: 'Password',
            prefixIcon: Icon(Icons.lock),
          ),
          obscureText: true,
        ),
        SizedBox(height: 16),
        CheckboxListTile(
          title: Text('Remember me'),
          value: rememberMe,
          onChanged: (value) {
            setState(() {
              rememberMe = value ?? false;
            });
          },
        ),
        SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: _isSubmitting
                ? null
                : () {
                    _handleLogin({
                      'email': emailController.text,
                      'password': passwordController.text,
                      'remember_me': rememberMe,
                    });
                  },
            child: _isSubmitting
                ? CircularProgressIndicator(color: Colors.white)
                : Text('Sign In'),
          ),
        ),
      ],
    );
  }
  
  Widget _buildSocialAuth() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(child: Divider()),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text('OR', style: TextStyle(color: Colors.grey)),
            ),
            Expanded(child: Divider()),
          ],
        ),
        SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildSocialButton(
              'Google',
              'assets/icons/google.png',
              () => _handleSocialLogin('google'),
            ),
            SizedBox(width: 16),
            _buildSocialButton(
              'Apple',
              'assets/icons/apple.png',
              () => _handleSocialLogin('apple'),
            ),
            SizedBox(width: 16),
            _buildSocialButton(
              'Facebook',
              'assets/icons/facebook.png',
              () => _handleSocialLogin('facebook'),
            ),
          ],
        ),
      ],
    );
  }
  
  Widget _buildSocialButton(String provider, String icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: EdgeInsets.all(12),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Image.asset(icon, width: 24, height: 24),
      ),
    );
  }
  
  Future<void> _handleSocialLogin(String provider) async {
    setState(() {
      _isSubmitting = true;
      _error = null;
    });
    
    final response = await AuthService.socialLogin(provider);
    
    setState(() {
      _isSubmitting = false;
    });
    
    if (response.success) {
      final sessionManager = context.read<SessionManager>();
      await sessionManager.createSession(response.data!);
      
      if (widget.onSuccess != null) {
        widget.onSuccess!();
      } else {
        Navigator.of(context).pushReplacementNamed('/home');
      }
    } else {
      setState(() {
        _error = response.error?.message;
      });
    }
  }
  
  Widget _buildFooter() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Text("Don't have an account? "),
        TextButton(
          onPressed: _navigateToRegister,
          child: Text('Sign Up'),
        ),
      ],
    );
  }
}
```

## 12.2 Auth Service

```dart
// lib/auth/services/auth_service.dart
import '../api/api_client.dart';
import '../models/auth_response.dart';
import '../models/api_response.dart';

class AuthService {
  static final ApiClient _client = ApiClient();
  
  /// Login with email and password
  static Future<ApiResponse<AuthResponse>> login({
    required String email,
    required String password,
    bool rememberMe = false,
  }) async {
    try {
      final response = await _client.post(
        '/auth/login',
        data: {
          'email': email,
          'password': password,
          'remember_me': rememberMe,
        },
      );
      
      final authResponse = AuthResponse.fromJson(response.data);
      return ApiResponse.success(authResponse);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Register new user
  static Future<ApiResponse<AuthResponse>> register(
    Map<String, dynamic> data,
  ) async {
    try {
      final response = await _client.post(
        '/auth/register',
        data: data,
      );
      
      final authResponse = AuthResponse.fromJson(response.data);
      return ApiResponse.success(authResponse);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Social login
  static Future<ApiResponse<AuthResponse>> socialLogin(
    String provider,
  ) async {
    try {
      final response = await _client.post(
        '/auth/social/$provider',
      );
      
      final authResponse = AuthResponse.fromJson(response.data);
      return ApiResponse.success(authResponse);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Send OTP
  static Future<ApiResponse<Map<String, dynamic>>> sendOtp({
    required String email,
    required String type,
  }) async {
    try {
      final response = await _client.post(
        '/auth/otp/send',
        data: {
          'email': email,
          'type': type,
        },
      );
      
      return ApiResponse.success(response.data);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Verify OTP
  static Future<ApiResponse<AuthResponse>> verifyOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _client.post(
        '/auth/otp/verify',
        data: {
          'email': email,
          'otp': otp,
        },
      );
      
      final authResponse = AuthResponse.fromJson(response.data);
      return ApiResponse.success(authResponse);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Send password reset OTP
  static Future<ApiResponse<Map<String, dynamic>>> sendPasswordResetOtp(
    String email,
  ) async {
    try {
      final response = await _client.post(
        '/auth/password/reset/send',
        data: {'email': email},
      );
      
      return ApiResponse.success(response.data);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Verify password reset OTP
  static Future<ApiResponse<Map<String, dynamic>>> verifyPasswordResetOtp({
    required String email,
    required String otp,
  }) async {
    try {
      final response = await _client.post(
        '/auth/password/reset/verify',
        data: {
          'email': email,
          'otp': otp,
        },
      );
      
      return ApiResponse.success(response.data);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
  
  /// Reset password
  static Future<ApiResponse<Map<String, dynamic>>> resetPassword({
    required String email,
    required String otp,
    required String newPassword,
  }) async {
    try {
      final response = await _client.post(
        '/auth/password/reset',
        data: {
          'email': email,
          'otp': otp,
          'new_password': newPassword,
        },
      );
      
      return ApiResponse.success(response.data);
    } catch (e) {
      return ApiResponse.error(e as ApiError);
    }
  }
}
```

## 12.3 Auth Response Model

```dart
// lib/auth/models/auth_response.dart
class AuthResponse {
  final String accessToken;
  final String refreshToken;
  final String sessionId;
  final UserModel user;
  final int expiresIn;
  
  AuthResponse({
    required this.accessToken,
    required this.refreshToken,
    required this.sessionId,
    required this.user,
    required this.expiresIn,
  });
  
  factory AuthResponse.fromJson(Map<String, dynamic> json) {
    return AuthResponse(
      accessToken: json['access_token'],
      refreshToken: json['refresh_token'],
      sessionId: json['session_id'],
      user: UserModel.fromJson(json['user']),
      expiresIn: json['expires_in'],
    );
  }
}

class UserModel {
  final String id;
  final String email;
  final String? firstName;
  final String? lastName;
  final String? phoneNumber;
  final String? avatar;
  final bool emailVerified;
  final bool phoneVerified;
  final Map<String, dynamic>? metadata;
  
  UserModel({
    required this.id,
    required this.email,
    this.firstName,
    this.lastName,
    this.phoneNumber,
    this.avatar,
    required this.emailVerified,
    required this.phoneVerified,
    this.metadata,
  });
  
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'],
      email: json['email'],
      firstName: json['first_name'],
      lastName: json['last_name'],
      phoneNumber: json['phone_number'],
      avatar: json['avatar'],
      emailVerified: json['email_verified'] ?? false,
      phoneVerified: json['phone_verified'] ?? false,
      metadata: json['metadata'],
    );
  }
}
```

Continue to [Part 12b: Additional Auth Pages](./part12b-flutter-pages-continued.md)
