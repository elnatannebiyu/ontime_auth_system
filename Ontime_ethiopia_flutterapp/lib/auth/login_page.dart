import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'tenant_auth_client.dart';
import 'secure_token_store.dart';
import '../core/widgets/auth_layout.dart';
import '../core/widgets/social_auth_buttons.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/version_badge.dart';
import '../core/services/social_auth.dart';
import 'services/simple_session_manager.dart';

class LoginPage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;
  final ThemeController themeController;

  const LoginPage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
    required this.themeController,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _username = TextEditingController(); // email-as-username supported by backend
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
  final bool _remember = true; // deprecated in minimal UI (kept for potential future use)

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final sessionManager = SimpleSessionManager();
      
      // Login through session manager
      await sessionManager.login(
        email: _username.text.trim(),
        password: _password.text,
        tenantId: widget.tenantId,
      );
      
      // Verify login by checking user info
      await widget.api.me();
      
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } on DioException catch (e) {
      final data = e.response?.data;
      final detail = (data is Map && data['detail'] != null) ? '${data['detail']}' : e.message;
      setState(() {
        _error = detail ?? 'Login failed';
      });
    } catch (e) {
      setState(() {
        _error = 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthLayout(
        title: 'Welcome back',
        subtitle: 'Sign in to continue',
        actions: [
          IconButton(
            tooltip: 'Toggle dark mode',
            onPressed: widget.themeController.toggleTheme,
            icon: const Icon(Icons.brightness_6_outlined),
          ),
        ],
        footer: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).pushReplacementNamed('/register'),
            child: const Text('Create an account'),
          ),
        ),
        bottom: const VersionBadge(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Social sign-in buttons
            SocialAuthButtons(
              onGoogle: () async {
                final service = const SocialAuthService();
                try {
                  await service.signInWithGoogle();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Google sign-in coming soon')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Google sign-in error: $e')),
                  );
                }
              },
              onApple: () async {
                final service = const SocialAuthService();
                try {
                  await service.signInWithApple();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Apple sign-in coming soon')),
                  );
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Apple sign-in error: $e')),
                  );
                }
              },
              showApple: Theme.of(context).platform == TargetPlatform.iOS,
            ),
            const SizedBox(height: 8),

            if (_error != null)
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.red.withOpacity(.25)),
                ),
                child: Text(_error!, style: const TextStyle(color: Colors.red)),
              ),
            // Minimal email/password form
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _username,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.alternate_email),
                      labelText: 'Email or username',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter your email/username' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure,
                    onFieldSubmitted: (_) => _login(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty) ? 'Enter password' : null,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Sign in'),
                    ),
                  ),
                ],
              ),
            ),

            // Phone OTP entry point disabled (coming soon)
            TextButton(
              onPressed: null,
              child: const Text('Use phone (coming soon)'),
            ),
          ],
        ),
      ),
    );
  }
}
