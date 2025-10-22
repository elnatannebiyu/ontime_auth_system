// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'tenant_auth_client.dart';
import '../api_client.dart';
import '../core/widgets/auth_layout.dart';
import '../core/widgets/social_auth_buttons.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/version_badge.dart';
import '../core/services/social_auth.dart';
import '../config.dart';
import 'services/simple_session_manager.dart';
import '../core/notifications/notification_permission_manager.dart';
import '../core/notifications/fcm_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/notifications/notification_inbox.dart';

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
  final _username =
      TextEditingController(); // email-as-username supported by backend
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;
// deprecated in minimal UI (kept for potential future use)

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _maybeShowFirstLoginAnnouncement() async {
    try {
      // Resolve current user id to scope cache per account
      int? userId;
      try {
        final me = await ApiClient().get('/me/');
        final data = me.data;
        if (data is Map && data['id'] is int) {
          userId = data['id'] as int;
        }
      } catch (_) {}
      final res = await ApiClient().get('/channels/announcements/first-login/');
      final data = res.data;
      if (!mounted) return;
      if (data is Map) {
        final title = (data['title'] as String?)?.trim();
        final body = (data['body'] as String?)?.trim();
        if ((title != null && title.isNotEmpty) || (body != null && body.isNotEmpty)) {
          // Suppress duplicates: if the same content was already shown for this tenant, skip.
          final prefs = await SharedPreferences.getInstance();
          final tenant = widget.tenantId;
          final userKeyPart = userId != null ? '_u${userId}' : '';
          final contentKey = 'first_login_announcement_${tenant}${userKeyPart}_hash';
          final contentVal = '${title ?? ''}\n${body ?? ''}';
          final lastShown = prefs.getString(contentKey);
          if (lastShown == contentVal) {
            return; // Already shown this exact content
          }
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: Text(title?.isNotEmpty == true ? title! : 'Notice'),
              content: Text(body?.isNotEmpty == true ? body! : ''),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('OK'),
                ),
              ],
            ),
          );
          // Remember that we've shown this content so we don't repeat it next login
          await prefs.setString(contentKey, contentVal);
          // Save to inbox for later viewing
          await NotificationInbox.add(NotificationItem(
            title: title ?? 'Notice',
            body: body ?? '',
            timestamp: DateTime.now(),
          ));
        }
      }
    } on DioException catch (e) {
      // If backend does not have the endpoint yet, ignore 404 gracefully
      if (e.response?.statusCode == 404) {
        return;
      }
      // Ignore other failures silently for this optional UX
    } catch (_) {
      // no-op
    }
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
      // Optionally show backend-provided first-login announcement (de-duped and saved to inbox)
      await _maybeShowFirstLoginAnnouncement();

      // Ask for notifications permission with enterprise-grade flow
      if (mounted) {
        await NotificationPermissionManager().ensurePermissionFlow(context);
      }

      // Register FCM token with backend now that we are authenticated
      await FcmManager().ensureRegisteredWithBackend();

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      final detail = (data is Map && data['detail'] != null)
          ? '${data['detail']}'
          : (e.message ?? '');
      String uiMsg = 'Login failed';
      if (detail == 'password_auth_not_set') {
        uiMsg =
            'This account was created with Google. Use “Continue with Google” or set a password first.';
      } else if (detail ==
          'No active account found with the given credentials') {
        uiMsg = 'Incorrect email or password.';
      } else if (code == 403 && detail.contains('Not a member of this tenant')) {
        uiMsg = "Your account isn't a member of this tenant ('${widget.tenantId}'). Contact support or switch tenant.";
      } else if (detail.isNotEmpty) {
        uiMsg = detail;
      }
      setState(() {
        _error = uiMsg;
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
            onPressed: () =>
                Navigator.of(context).pushReplacementNamed('/register'),
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
                final service = SocialAuthService(serverClientId: kGoogleWebClientId);
                try {
                  // Force account chooser to appear after a prior social session
                  final result = await service.signInWithGoogle(signOutFirst: true);
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
                        ? (data['error'] as String)
                        : '';
                    if (code == 404 && errKey == 'user_not_found') {
                      // Ask the user for permission to create a new account
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
                      // Step 2: create account and login
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
                  // Optional: show backend-provided first-login announcement for parity with password login
                  await _maybeShowFirstLoginAnnouncement();
                  // Ask for notifications permission before registering FCM to ensure APNs is available on iOS
                  if (mounted) {
                    await NotificationPermissionManager().ensurePermissionFlow(context);
                  }
                  // Now register FCM token with backend
                  await FcmManager().ensureRegisteredWithBackend();
                  if (!mounted) return;
                  Navigator.of(context)
                      .pushNamedAndRemoveUntil('/home', (_) => false);
                } on DioException catch (e) {
                  // If server enforced update (426), let the global modal handle UX
                  if (e.response?.statusCode == 426) {
                    return;
                  }
                  final data = e.response?.data;
                  final err = (data is Map && data['error'] is String)
                      ? data['error'] as String
                      : e.message ?? 'Google sign-in failed';
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text(err)));
                } catch (e) {
                  // If a 426 slipped through as a generic error, do not show snackbar
                  final msg = '$e';
                  if (msg.contains('426') || msg.contains('APP_UPDATE_REQUIRED')) {
                    return;
                  }
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
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Enter your email/username'
                        : null,
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
                        icon: Icon(
                            _obscure ? Icons.visibility : Icons.visibility_off),
                        onPressed: () => setState(() => _obscure = !_obscure),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'Enter password' : null,
                  ),
                  const SizedBox(height: 12),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: FilledButton(
                      onPressed: _loading ? null : _login,
                      child: _loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2))
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
