// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:ontime_ethiopia_flutterapp/auth/simple_password_reset_page.dart';
import 'tenant_auth_client.dart';
import '../api_client.dart';
import '../core/widgets/auth_layout.dart';
import '../core/widgets/social_auth_buttons.dart';
import '../core/theme/theme_controller.dart';
import '../core/widgets/version_badge.dart';
import '../core/services/social_auth.dart';
import '../config.dart';
import 'services/simple_session_manager.dart';
import '../core/notifications/fcm_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../core/notifications/notification_inbox.dart';
import '../core/localization/l10n.dart';

class LoginPage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;
  final ThemeController themeController;
  final LocalizationController localizationController;

  const LoginPage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
    required this.themeController,
    required this.localizationController,
  });

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  // Feature flag to show/hide legacy email/password login UX without deleting code
  static const bool _kEnablePasswordLogin = true;
  final _formKey = GlobalKey<FormState>();
  final _username =
      TextEditingController(); // email-as-username supported by backend
  final _password = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  bool _inFlight = false; // guard against double submits
  String? _error;
  bool _socialLoading = false; // loading state for Google/Apple flows
// deprecated in minimal UI (kept for potential future use)
  bool get _googleSignInEnabled {
    // Allow Google Sign-In on all platforms; FCM/notifications remain
    // disabled on iOS via separate Platform checks.
    return true;
  }

  @override
  void initState() {
    super.initState();
  }

  String _t(String key) => widget.localizationController.t(key);

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
        // Seed short-lived cache to avoid immediate re-fetch on Home
        if (data is Map<String, dynamic>) {
          ApiClient().setLastMe(data);
        }
      } catch (_) {}
      final res = await ApiClient().get('/channels/announcements/first-login/');
      final data = res.data;
      if (!mounted) return;
      if (data is Map) {
        final title = (data['title'] as String?)?.trim();
        final body = (data['body'] as String?)?.trim();
        if ((title != null && title.isNotEmpty) ||
            (body != null && body.isNotEmpty)) {
          // Suppress duplicates: if the same content was already shown for this tenant, skip.
          final prefs = await SharedPreferences.getInstance();
          final tenant = widget.tenantId;
          final userKeyPart = userId != null ? '_u$userId' : '';
          final contentKey =
              'first_login_announcement_$tenant${userKeyPart}_hash';
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

  Future<void> _forgotPassword() async {
    if (_loading) return;

    // Navigate to password reset page
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SimplePasswordResetPage(
          tenantId: widget.tenantId,
          localizationController: widget.localizationController,
        ),
      ),
    );
  }

  Future<void> _login() async {
    if (_loading || _inFlight) return;
    // Basic email validation to prevent typos like `gmail,com`
    final email = _username.text.trim();
    final emailOk = RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]{2,}$').hasMatch(email);
    if (!emailOk) {
      setState(() {
        _error = 'Enter a valid email address.';
      });
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    _inFlight = true;

    try {
      final sessionManager = SimpleSessionManager();

      // Login through session manager
      await sessionManager.login(
        email: _username.text.trim(),
        password: _password.text,
        tenantId: widget.tenantId,
      );

      // Optionally show backend-provided first-login announcement (de-duped and saved to inbox)
      await _maybeShowFirstLoginAnnouncement();

      if (!Platform.isIOS) {
        try {
          await FcmManager().ensureRegisteredWithBackend();
        } catch (_) {}
      }

      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/home', (_) => false);
    } on DioException catch (e) {
      final code = e.response?.statusCode ?? 0;
      final data = e.response?.data;
      final rawDetail = (data is Map && data['detail'] != null)
          ? '${data['detail']}'
          : (e.message ?? '');
      final detail = rawDetail.toString();

// Also check 'error' field for structured errors
      final errorCode = (data is Map && data['error'] is String)
          ? data['error'] as String
          : '';

// Normalize common backend responses
      String uiMsg = 'Login failed';
      if (detail == 'password_auth_not_set' ||
          errorCode == 'password_auth_not_set') {
        uiMsg =
            'This account was created with Google. Use "Continue with Google" instead.';
        // Do NOT navigate to password reset - social accounts can't reset non-existent password
      }
      if (detail == 'password_auth_not_set') {
        uiMsg =
            'This account was created with Google. Use “Continue with Google” or set a password first.';
      } else if (detail.contains('No active account found')) {
        uiMsg = 'Incorrect email or password.';
      } else if (code == 403 &&
          detail.contains('Not a member of this tenant')) {
        uiMsg =
            "Your account isn't a member of this tenant ('${widget.tenantId}').";
      } else if (code == 429 || detail.toLowerCase().contains('too many')) {
        uiMsg = 'Too many attempts. Please wait a minute and try again.';
      } else if (detail.toLowerCase().contains('locked')) {
        uiMsg =
            'Account temporarily locked due to failed attempts. Try again later.';
      } else if (detail.isNotEmpty) {
        uiMsg = detail;
      }
      setState(() {
        _error = uiMsg;
      });
    } catch (e) {
      if (kDebugMode) {
        debugPrint('[login] non-Dio error: $e');
      }
      setState(() {
        _error = kDebugMode ? '$e' : 'Something went wrong. Please try again.';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
      _inFlight = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.localizationController,
      builder: (context, _) {
        final lang = widget.localizationController.language;
        String langLabel;
        switch (lang) {
          case AppLanguage.am:
            langLabel = 'AM';
            break;
          case AppLanguage.om:
            langLabel = 'OM';
            break;
          case AppLanguage.en:
            langLabel = 'EN';
            break;
        }
        return Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                // Top-right language selector, slightly lower from the very top
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: PopupMenuButton<AppLanguage>(
                      tooltip: _t('switch_language'),
                      onSelected: (value) {
                        widget.localizationController.setLanguage(value);
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: AppLanguage.en,
                          child: Text(_t('english')),
                        ),
                        PopupMenuItem(
                          value: AppLanguage.am,
                          child: Text(_t('amharic')),
                        ),
                        PopupMenuItem(
                          value: AppLanguage.om,
                          child: Text(_t('oromo')),
                        ),
                      ],
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(_t('choose_language')),
                          const SizedBox(width: 8),
                          const Icon(Icons.language, size: 18),
                          const SizedBox(width: 4),
                          Text(langLabel),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AuthLayout(
                    title: _t('welcome_back'),
                    subtitle: _t('login_subtitle'),
                    actions: [
                      IconButton(
                        tooltip: _t('toggle_dark_mode'),
                        onPressed: widget.themeController.toggleTheme,
                        icon: const Icon(Icons.brightness_6_outlined),
                      ),
                    ],
                    footer: null,
                    bottom: const VersionBadge(),
                    child: _socialLoading
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // Social sign-in buttons
                              SocialAuthButtons(
                                googleLabel:
                                    _t('sign_in_or_sign_up_with_google'),
                                appleLabel: _t('sign_in_or_sign_up_with_apple'),
                                onGoogle: !_googleSignInEnabled
                                    ? null
                                    : () async {
                                        final service = SocialAuthService(
                                            serverClientId: kGoogleWebClientId);
                                        try {
                                          setState(() {
                                            _socialLoading = true;
                                            _error = null;
                                          });
                                          // Force account chooser to appear after a prior social session
                                          final result =
                                              await service.signInWithGoogle(
                                                  signOutFirst: true);
                                          // Step 1: attempt login without creating a new account
                                          Tokens tokens;
                                          try {
                                            tokens =
                                                await widget.api.socialLogin(
                                              tenantId: widget.tenantId,
                                              provider: 'google',
                                              token: result.idToken!,
                                              allowCreate: false,
                                            );
                                          } on DioException catch (e) {
                                            final code =
                                                e.response?.statusCode ?? 0;
                                            final data = e.response?.data;
                                            final errKey = (data is Map &&
                                                    data['error'] is String)
                                                ? (data['error'] as String)
                                                : '';
                                            if (code == 404 &&
                                                errKey == 'user_not_found') {
                                              // Ask the user for permission to create a new account
                                              final confirmed =
                                                  await showDialog<bool>(
                                                context: context,
                                                builder: (ctx) => AlertDialog(
                                                  title: Text(_t(
                                                      'create_new_account_title')),
                                                  content: Text(_t(
                                                      'create_new_account_body')),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () =>
                                                          Navigator.of(ctx)
                                                              .pop(false),
                                                      child: Text(
                                                          _t('dialog_cancel')),
                                                    ),
                                                    FilledButton(
                                                      onPressed: () =>
                                                          Navigator.of(ctx)
                                                              .pop(true),
                                                      child: Text(
                                                          _t('dialog_create')),
                                                    ),
                                                  ],
                                                ),
                                              );
                                              if (confirmed != true) return;
                                              // Step 2: create account and login
                                              tokens =
                                                  await widget.api.socialLogin(
                                                tenantId: widget.tenantId,
                                                provider: 'google',
                                                token: result.idToken!,
                                                allowCreate: true,
                                                userData: {
                                                  if (result.email != null)
                                                    'email': result.email,
                                                  if (result.displayName !=
                                                      null)
                                                    'name': result.displayName,
                                                },
                                              );
                                            } else {
                                              rethrow;
                                            }
                                          }
                                          await widget.tokenStore.setTokens(
                                              tokens.access, tokens.refresh);
                                          await widget.api.me();
                                          // Optional: show backend-provided first-login announcement for parity with password login
                                          await _maybeShowFirstLoginAnnouncement();
                                          if (!Platform.isIOS) {
                                            if (mounted) {
                                              // Notification permission is requested only when user enables reminders.
                                            }
                                            await FcmManager()
                                                .ensureRegisteredWithBackend();
                                          }
                                          if (!mounted) return;
                                          Navigator.of(context)
                                              .pushNamedAndRemoveUntil(
                                                  '/home', (_) => false);
                                        } on DioException catch (e) {
                                          // If server enforced update (426) or explicit APP_UPDATE_REQUIRED
                                          // code, let the global update handler show the dialog and do not
                                          // surface a red error banner here.
                                          final status = e.response?.statusCode;
                                          final data = e.response?.data;
                                          final appUpdateCode = (data is Map &&
                                              data['code'] is String &&
                                              data['code'] ==
                                                  'APP_UPDATE_REQUIRED');
                                          if (status == 426 || appUpdateCode) {
                                            if (mounted) {
                                              setState(
                                                  () => _socialLoading = false);
                                            }
                                            return;
                                          }
                                          if (mounted) {
                                            setState(() {
                                              _socialLoading = false;
                                              _error = kDebugMode
                                                  ? 'Google sign-in error: $e'
                                                  : _t('google_signin_failed');
                                            });
                                          }
                                        } catch (e) {
                                          // If a 426 slipped through as a generic error, do not show snackbar
                                          final msg = '$e';
                                          if (msg.contains('426') ||
                                              msg.contains(
                                                  'APP_UPDATE_REQUIRED')) {
                                            if (mounted) {
                                              setState(
                                                  () => _socialLoading = false);
                                            }
                                            return;
                                          }
                                          // If user cancelled/no account selected, ignore quietly
                                          if (msg
                                                  .toLowerCase()
                                                  .contains('aborted') ||
                                              msg
                                                  .toLowerCase()
                                                  .contains('canceled') ||
                                              msg
                                                  .toLowerCase()
                                                  .contains('cancelled')) {
                                            if (mounted) {
                                              setState(
                                                  () => _socialLoading = false);
                                            }
                                            return;
                                          }
                                          if (mounted) {
                                            setState(() {
                                              _socialLoading = false;
                                              _error = kDebugMode
                                                  ? 'Google sign-in error: $e'
                                                  : _t('google_signin_failed');
                                            });
                                          }
                                        }
                                      },
                                onApple: () async {
                                  final service = SocialAuthService();
                                  try {
                                    setState(() {
                                      _socialLoading = true;
                                      _error = null;
                                    });
                                    await service.signInWithApple();
                                    if (mounted) {
                                      setState(() {
                                        _socialLoading = false;
                                        _error = _t('apple_signin_coming_soon');
                                      });
                                    }
                                  } catch (e) {
                                    final msg = '$e';
                                    // Treat user cancellation quietly
                                    if (msg.toLowerCase().contains('aborted') ||
                                        msg
                                            .toLowerCase()
                                            .contains('canceled') ||
                                        msg
                                            .toLowerCase()
                                            .contains('cancelled')) {
                                      if (mounted) {
                                        setState(() => _socialLoading = false);
                                      }
                                      return;
                                    }
                                    if (mounted) {
                                      setState(() {
                                        _socialLoading = false;
                                        _error = kDebugMode
                                            ? 'Apple sign-in error: $e'
                                            : _t('apple_signin_failed');
                                      });
                                    }
                                  }
                                },
                                showApple: Theme.of(context).platform ==
                                    TargetPlatform.iOS,
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
                                    border: Border.all(
                                        color: Colors.red.withOpacity(.25)),
                                  ),
                                  child: Text(_error!,
                                      style:
                                          const TextStyle(color: Colors.red)),
                                ),
                              // Minimal email/password form
                              if (_kEnablePasswordLogin)
                                Form(
                                  key: _formKey,
                                  child: Column(
                                    children: [
                                      TextFormField(
                                        controller: _username,
                                        autofocus: true,
                                        textInputAction: TextInputAction.next,
                                        decoration: InputDecoration(
                                          prefixIcon:
                                              const Icon(Icons.alternate_email),
                                          labelText: _t('email_or_username'),
                                          border: const OutlineInputBorder(),
                                        ),
                                        validator: (v) => (v == null ||
                                                v.trim().isEmpty)
                                            ? _t('email_or_username_required')
                                            : null,
                                      ),
                                      const SizedBox(height: 12),
                                      TextFormField(
                                        controller: _password,
                                        obscureText: _obscure,
                                        onFieldSubmitted: (_) => _login(),
                                        decoration: InputDecoration(
                                          prefixIcon:
                                              const Icon(Icons.lock_outline),
                                          labelText: _t('password_label'),
                                          border: const OutlineInputBorder(),
                                          suffixIcon: IconButton(
                                            icon: Icon(_obscure
                                                ? Icons.visibility
                                                : Icons.visibility_off),
                                            onPressed: () => setState(
                                                () => _obscure = !_obscure),
                                          ),
                                        ),
                                        validator: (v) =>
                                            (v == null || v.isEmpty)
                                                ? _t('password_required')
                                                : null,
                                      ),
                                      const SizedBox(height: 12),
                                      Align(
                                        alignment: Alignment.centerRight,
                                        child: TextButton(
                                          onPressed:
                                              _loading ? null : _forgotPassword,
                                          child: Text(_t('forgot_password')),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: double.infinity,
                                        height: 48,
                                        child: FilledButton(
                                          onPressed: _loading ? null : _login,
                                          child: _loading
                                              ? const SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2))
                                              : Text(_t('sign_in')),
                                        ),
                                      ),

                                      // Phone OTP entry point disabled (coming soon)
                                      if (_kEnablePasswordLogin)
                                        TextButton(
                                          onPressed: null,
                                          child:
                                              Text(_t('use_phone_coming_soon')),
                                        ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
