import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'tenant_auth_client.dart';
import '../api_client.dart';
import '../core/widgets/auth_layout.dart';
import '../core/widgets/social_auth_buttons.dart';
import '../core/widgets/version_badge.dart';
import '../core/services/social_auth.dart';
import '../core/utils/phone_input_formatter.dart';
import '../core/theme/theme_controller.dart';
import '../core/notifications/notification_permission_manager.dart';

class RegisterPage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;
  final ThemeController themeController;

  const RegisterPage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
    required this.themeController,
  });

  @override
  State<RegisterPage> createState() => _RegisterPageState();
}

class _RegisterPageState extends State<RegisterPage> {
  final _formKey = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure1 = true;
  bool _obscure2 = true;
  bool _loading = false;
  String? _error;
  bool _remember = true;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _register() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final tenant = widget.tenantId;
      widget.api.setTenant(tenant);
      final tokens = await widget.api.register(
        tenantId: tenant,
        email: _email.text.trim(),
        password: _password.text,
      );
      if (_remember) {
        await widget.tokenStore.setTokens(tokens.access, tokens.refresh);
      } else {
        ApiClient().setAccessToken(tokens.access);
      }
      // Post-register guard: ensure membership/access to tenant
      try {
        await widget.api.me();
        if (mounted) {
          await NotificationPermissionManager().ensurePermissionFlow(context);
        }
        if (!mounted) return;
        Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
      } on DioException catch (e) {
        await widget.tokenStore.clear();
        final data = e.response?.data;
        String message = e.message ??
            'Registration succeeded, but access to this tenant is not permitted';
        if (data is Map && data['detail'] != null) {
          message = '${data['detail']}';
        }
        setState(() => _error = message);
        return;
      }
    } on DioException catch (e) {
      final data = e.response?.data;
      String message = e.message ?? 'Registration failed';
      // Prefer field-specific errors
      if (data is Map) {
        final msgs = <String>[];
        void collect(key) {
          final v = data[key];
          if (v is List) {
            msgs.addAll(v.map((x) => '$key: $x'));
          } else if (v is String) {
            msgs.add('$key: $v');
          }
        }
        // Collect common DRF error shapes
        for (final k in ['email', 'password', 'non_field_errors', 'detail']) {
          collect(k);
        }
        if (msgs.isNotEmpty) {
          message = msgs.join('\n');
        }
      }
      setState(() => _error = message);
    } catch (e) {
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: AuthLayout(
        title: 'Create account',
        subtitle: 'Join with your email and a strong password',
        actions: [
          IconButton(
            tooltip: 'Toggle dark mode',
            icon: Icon(
              widget.themeController.themeMode == ThemeMode.dark
                  ? Icons.light_mode
                  : Icons.dark_mode,
            ),
            onPressed: widget.themeController.toggleTheme,
          ),
        ],
        footer: Center(
          child: TextButton(
            onPressed: () {
              Navigator.of(context).pushReplacementNamed('/login');
            },
            child: const Text('Already have an account? Sign in'),
          ),
        ),
        bottom: const VersionBadge(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Social sign-in buttons
            SocialAuthButtons(
              onGoogle: () async {
                final service = SocialAuthService();
                try {
                  final result = await service.signInWithGoogle();
                  // Step 1: attempt login without creating a new account
                  Tokens tokens;
                  try {
                    tokens = await widget.api.socialLogin(
                      tenantId: widget.tenantId,
                      provider: 'google',
                      token: result.idToken!,
                      allowCreate: false,
                    );
                  } on DioException catch (e) {
                    final code = e.response?.statusCode ?? 0;
                    final data = e.response?.data;
                    final errKey = (data is Map && data['error'] is String)
                        ? data['error'] as String
                        : '';
                    if (code == 404 && errKey == 'user_not_found') {
                      // Ask to create the account
                      final confirmed = await showDialog<bool>(
                        context: context,
                        builder: (ctx) => AlertDialog(
                          title: const Text('Create new account?'),
                          content: Text(
                              'No account exists for ${result.email ?? 'this Google account'}. Create one now?'),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.of(ctx).pop(false),
                              child: const Text('Cancel'),
                            ),
                            FilledButton(
                              onPressed: () => Navigator.of(ctx).pop(true),
                              child: const Text('Create'),
                            ),
                          ],
                        ),
                      );
                      if (confirmed != true) return;
                      tokens = await widget.api.socialLogin(
                        tenantId: widget.tenantId,
                        provider: 'google',
                        token: result.idToken!,
                        allowCreate: true,
                        userData: {
                          if (result.email != null) 'email': result.email,
                          if (result.displayName != null) 'name': result.displayName,
                        },
                      );
                    } else {
                      rethrow;
                    }
                  }
                  await widget.tokenStore.setTokens(tokens.access, tokens.refresh);
                  await widget.api.me();
                  if (mounted) {
                    await NotificationPermissionManager().ensurePermissionFlow(context);
                  }
                  if (!mounted) return;
                  Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
                } on DioException catch (e) {
                  final data = e.response?.data;
                  final err = (data is Map && data['error'] is String)
                      ? data['error'] as String
                      : e.message ?? 'Google sign-in failed';
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(err)));
                } catch (e) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Google sign-in error: $e')),
                  );
                }
              },
              onApple: () async {
                final service = SocialAuthService();
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
                child: Text(_error!,
                    style: const TextStyle(color: Colors.red)),
              ),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _email,
                    autofocus: true,
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.mail_outline),
                      labelText: 'Email',
                      border: OutlineInputBorder(),
                    ),
                    validator: (v) {
                      final val = v?.trim() ?? '';
                      if (val.isEmpty) return 'Enter email';
                      final emailRe = RegExp(r'^.+@.+\..+$');
                      if (!emailRe.hasMatch(val)) return 'Enter a valid email';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  // Optional phone number (not required)
                  TextFormField(
                    keyboardType: TextInputType.phone,
                    inputFormatters: [SimplePhoneInputFormatter(defaultDialCode: '+251')],
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.phone_outlined),
                      labelText: 'Phone (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _password,
                    obscureText: _obscure1,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_outline),
                      labelText: 'Password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure1 ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure1 = !_obscure1),
                      ),
                    ),
                    validator: (v) {
                      final val = v ?? '';
                      if (val.isEmpty) return 'Enter password';
                      if (val.length < 8) return 'Password must be at least 8 characters';
                      final upper = RegExp(r'[A-Z]');
                      final lower = RegExp(r'[a-z]');
                      final digit = RegExp(r'\d');
                      final special = RegExp(r'[!@#\$%\^&\*(),.?":{}|<>]');
                      if (!upper.hasMatch(val)) return 'Password must include an uppercase letter';
                      if (!lower.hasMatch(val)) return 'Password must include a lowercase letter';
                      if (!digit.hasMatch(val)) return 'Password must include a number';
                      if (!special.hasMatch(val)) return 'Password must include a special character';
                      return null;
                    },
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirm,
                    obscureText: _obscure2,
                    onFieldSubmitted: (_) => _register(),
                    decoration: InputDecoration(
                      prefixIcon: const Icon(Icons.lock_reset),
                      labelText: 'Confirm password',
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(_obscure2 ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure2 = !_obscure2),
                      ),
                    ),
                    validator: (v) => (v ?? '') != _password.text
                        ? 'Passwords do not match'
                        : null,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Checkbox(
                        value: _remember,
                        onChanged: (v) => setState(() => _remember = v ?? true),
                      ),
                      const Text('Remember me'),
                      const Spacer(),
                      TextButton(
                        onPressed: () {},
                        child: const Text('Need help?'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _register,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
                          : const Text('Create account'),
                    ),
                  ),
                ],
              ),
            ),
            // Helper removed for ultra-minimal
          ],
        ),
      ),
    );
  }
}
