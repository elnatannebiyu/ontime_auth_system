import 'dart:async';

import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../auth/tenant_auth_client.dart';
import '../auth/services/simple_session_manager.dart';
import '../core/widgets/brand_title.dart';
import '../api_client.dart';
import '../core/widgets/offline_banner.dart';
import '../core/localization/l10n.dart';

class ProfilePage extends StatefulWidget {
  final LocalizationController localizationController;

  const ProfilePage({
    super.key,
    required this.localizationController,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _api = AuthApi();
  // Removed unused SecureTokenStore; logout is centralized in SimpleSessionManager
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _me;
  bool _offline = false;
  StreamSubscription<List<ConnectivityResult>>? _connSub;

  bool _verifying = false;
  bool _verificationSent = false;
  int _verificationCooldown = 0;
  Timer? _verificationTimer;
  bool _pendingSuccessDialog = false;

  String _originalFirstName = '';
  String _originalLastName = '';
  bool _dirty = false;
  bool _editing = false;

  // Editable fields (example: first_name, last_name)
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();
  final _firstNameFocus = FocusNode();

  String _t(String key) => widget.localizationController.t(key);

  bool get _isEmailVerified {
    final v = _me?['email_verified'];
    if (v is bool) return v;
    if (v is String) {
      return v.toLowerCase() == 'true';
    }
    return false;
  }

  bool get _hasPassword {
    final v = _me?['has_password'];
    if (v is bool) return v;
    if (v is String) {
      return v.toLowerCase() == 'true';
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    _firstName.addListener(_onFieldsChanged);
    _lastName.addListener(_onFieldsChanged);
    _load();
    _connSub = Connectivity()
        .onConnectivityChanged
        .listen((List<ConnectivityResult> results) {
      final isOffline =
          results.isEmpty || results.every((r) => r == ConnectivityResult.none);
      if (!mounted) return;
      setState(() {
        _offline = isOffline;
      });
    });
  }

  @override
  void dispose() {
    _firstNameFocus.dispose();
    _firstName.dispose();
    _lastName.dispose();
    _verificationTimer?.cancel();
    _connSub?.cancel();
    super.dispose();
  }

  void _onFieldsChanged() {
    final fn = _firstName.text.trim();
    final ln = _lastName.text.trim();
    final isDirty = fn != _originalFirstName || ln != _originalLastName;
    if (isDirty != _dirty && mounted) {
      setState(() {
        _dirty = isDirty;
      });
    }
  }

  Future<void> _enablePassword() async {
    if (!_isEmailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('password_manage_requires_verified_email'))),
      );
      return;
    }

    final controller1 = TextEditingController();
    final controller2 = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_t('enable_password')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: controller1,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller2,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm password',
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(_t('cancel')),
              ),
              TextButton(
                onPressed: () {
                  if (controller1.text != controller2.text ||
                      controller1.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('Passwords do not match or are empty')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: Text(_t('enable_password')),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiClient().post('/me/enable-password/', data: {
        'new_password': controller1.text,
      });
      if (!mounted) return;

      // Clear token immediately to prevent double logout glitch
      // Backend revokes all sessions, so we clear locally before calling logout
      ApiClient().setAccessToken(null);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('password_enabled_logged_out'))),
      );

      // Logout will clean up cookies and navigate
      await SimpleSessionManager().logout();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } on DioException catch (e) {
      if (!mounted) return;

      String errorMsg = 'Failed to enable password';
      final data = e.response?.data;

      if (data is Map) {
        if (data['errors'] is List) {
          final errors = (data['errors'] as List).cast<String>();
          errorMsg = 'Password requirements:\n• ' + errors.join('\n• ');
        } else if (data['detail'] is String) {
          errorMsg = data['detail'] as String;
        }
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(errorMsg),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to enable password.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _disablePassword() async {
    if (!_isEmailVerified) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('password_manage_requires_verified_email'))),
      );
      return;
    }

    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_t('disable_password')),
            content: TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(
                labelText: 'Current password',
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(_t('cancel')),
              ),
              TextButton(
                onPressed: () {
                  if (controller.text.trim().isEmpty) {
                    ScaffoldMessenger.of(ctx).showSnackBar(
                      const SnackBar(
                          content: Text('Enter your current password')),
                    );
                    return;
                  }
                  Navigator.of(ctx).pop(true);
                },
                child: Text(_t('disable_password')),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      await ApiClient().post('/me/disable-password/', data: {
        'current_password': controller.text,
      });
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('password_disabled_logged_out'))),
      );
      await SimpleSessionManager().logout();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to disable password.')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  Future<void> _requestEmailVerification() async {
    if (_me == null || _isEmailVerified) return;
    if (_verificationCooldown > 0) return;
    setState(() {
      _verifying = true;
    });

    // Show a simple full-screen loading dialog while the request is in
    // progress so the user clearly sees that something is happening.
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return WillPopScope(
          onWillPop: () async => false,
          child: const Center(
            child: CircularProgressIndicator(),
          ),
        );
      },
    );
    try {
      await ApiClient().post('/me/request-email-verification/', data: {});
      if (!mounted) return;
      _verificationSent = true;
      _startVerificationCooldown();
      _pendingSuccessDialog = true;
    } catch (e) {
      if (!mounted) return;

      String message = _t('verification_email_failed');
      int? retryAfterSeconds;

      if (e is DioException) {
        final res = e.response;
        if (res != null && res.statusCode == 429) {
          final data = res.data;
          if (data is Map) {
            final error = data['error']?.toString();
            if (error == 'too_many_requests') {
              final ra = data['retry_after_seconds'];
              if (ra is int && ra > 0) {
                retryAfterSeconds = ra;
              }
              message =
                  'You have requested too many verification emails. Please wait about 1 hour and try again.';
            } else if (error == 'cooldown_active') {
              final ra = data['retry_after_seconds'];
              if (ra is int && ra > 0) {
                retryAfterSeconds = ra;
              }
              message =
                  'A verification email was recently sent. Please wait about 1 hour and check your inbox.';
            }
          }
        }
      }

      if (retryAfterSeconds != null) {
        _startVerificationCooldown(retryAfterSeconds);
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
        ),
      );
    } finally {
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
        setState(() {
          _verifying = false;
        });
        if (_pendingSuccessDialog) {
          _pendingSuccessDialog = false;
          // Show a simple confirmation dialog so the user clearly sees that
          // the email was sent, instead of only a transient snackbar.
          showDialog<void>(
            context: context,
            barrierDismissible: true,
            builder: (ctx) {
              return AlertDialog(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.mark_email_read_outlined,
                      color: Colors.green,
                      size: 48,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      _t('verification_email_sent'),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            },
          );
        }
      }
    }
  }

  void _startVerificationCooldown([int seconds = 60]) {
    _verificationTimer?.cancel();
    setState(() {
      _verificationCooldown = seconds;
    });
    _verificationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_verificationCooldown <= 1) {
        setState(() {
          _verificationCooldown = 0;
        });
        timer.cancel();
      } else {
        setState(() {
          _verificationCooldown -= 1;
        });
      }
    });
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    // Prime UI from cached profile if available so it works offline
    try {
      final cached = ApiClient().getCachedMe();
      if (cached != null) {
        _me = cached;
        _firstName.text = (cached['first_name'] ?? '').toString();
        _lastName.text = (cached['last_name'] ?? '').toString();
        _originalFirstName = _firstName.text.trim();
        _originalLastName = _lastName.text.trim();
        _dirty = false;
        _editing = false;
      }
    } catch (_) {}
    try {
      final me = await _api.me();
      _me = me;
      _firstName.text = (me['first_name'] ?? '').toString();
      _lastName.text = (me['last_name'] ?? '').toString();
      _originalFirstName = _firstName.text.trim();
      _originalLastName = _lastName.text.trim();
      _dirty = false;
      _editing = false;
    } catch (e) {
      // Leave any cached profile in place; just show error banner
      _error = _t('profile_load_error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = {
        'first_name': _firstName.text.trim(),
        'last_name': _lastName.text.trim(),
      };
      _me = await _api.updateProfile(payload);
      if (_me != null) {
        ApiClient().setLastMe(_me!);
        _originalFirstName = _firstName.text.trim();
        _originalLastName = _lastName.text.trim();
        _dirty = false;
        _editing = false;
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('profile_update_success'))),
      );
    } catch (e) {
      setState(() => _error = _t('profile_update_error'));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      // Route through the session manager so it also signs out of Google
      // and clears local tokens consistently across the app.
      await SimpleSessionManager().logout();
    } catch (_) {}
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  Future<void> _confirmDeleteAccount() async {
    final confirmed = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(_t('delete_account_title')),
            content: Text(_t('delete_account_body')),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: Text(_t('cancel')),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: TextButton.styleFrom(foregroundColor: Colors.red),
                child: Text(_t('delete_account')),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirmed || !mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await _api.deleteAccount();
      await SimpleSessionManager().logout();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('delete_account_success'))),
      );
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('delete_account_error'))),
      );
    } finally {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  String _initial() {
    final email = (_me?['email'] ?? '').toString().trim();
    final first = (_me?['first_name'] ?? '').toString().trim();
    final last = (_me?['last_name'] ?? '').toString().trim();
    final src =
        (first + last).trim().isNotEmpty ? (first + last).trim() : email;
    if (src.isEmpty) return '?';
    return src[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: BrandTitle(section: _t('profile')),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_offline || _error != null)
                    OfflineBanner(
                      title: _offline
                          ? _t('you_are_offline')
                          : _t('profile_load_error'),
                      subtitle: _offline
                          ? _t('some_actions_offline')
                          : (_error ?? ''),
                      onRetry: _load,
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                child: Text(
                                  _initial(),
                                  style: const TextStyle(
                                    fontSize: 20,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      (_me?['first_name'] ?? '')
                                              .toString()
                                              .trim()
                                              .isNotEmpty
                                          ? '${(_me?['first_name'] ?? '').toString().trim()} ${(_me?['last_name'] ?? '').toString().trim()}'
                                          : (_me?['email'] ?? '—').toString(),
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _me?['email']?.toString() ?? '—',
                                      style:
                                          Theme.of(context).textTheme.bodySmall,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Icon(
                                          _isEmailVerified
                                              ? Icons.verified
                                              : Icons.error_outline,
                                          size: 16,
                                          color: _isEmailVerified
                                              ? Colors.green
                                              : Colors.redAccent,
                                        ),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            _isEmailVerified
                                                ? _t('email_verified_banner')
                                                : _t(
                                                    'email_not_verified_banner'),
                                            style: Theme.of(context)
                                                .textTheme
                                                .bodySmall
                                                ?.copyWith(
                                                  color: _isEmailVerified
                                                      ? Colors.green
                                                      : Colors.redAccent,
                                                ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        if (!_isEmailVerified)
                                          TextButton(
                                            onPressed: (_loading ||
                                                    _verifying ||
                                                    _verificationCooldown > 0)
                                                ? null
                                                : _requestEmailVerification,
                                            child: Text(
                                              _verificationSent
                                                  ? _verificationCooldown > 0
                                                      ? '${_t('resend_email')} (${_verificationCooldown}s)'
                                                      : _t('resend_email')
                                                  : _verificationCooldown > 0
                                                      ? '${_t('verify_now')} (${_verificationCooldown}s)'
                                                      : _t('verify_now'),
                                            ),
                                          ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _t('profile_details'),
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                              InkWell(
                                borderRadius: BorderRadius.circular(4),
                                onTap: () {
                                  setState(() {
                                    if (_editing) {
                                      // Cancel: revert values and lock fields
                                      _firstName.text = _originalFirstName;
                                      _lastName.text = _originalLastName;
                                      _dirty = false;
                                      _editing = false;
                                    } else {
                                      _editing = true;
                                      _firstNameFocus.requestFocus();
                                    }
                                  });
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 4, vertical: 2),
                                  child: Text(
                                    _editing ? _t('cancel') : _t('edit'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(
                                            color: Theme.of(context)
                                                .colorScheme
                                                .primary),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _firstName,
                            focusNode: _firstNameFocus,
                            readOnly: !_editing,
                            decoration: InputDecoration(
                              labelText: _t('first_name'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _lastName,
                            readOnly: !_editing,
                            decoration: InputDecoration(
                              labelText: _t('last_name'),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          if (_editing && _dirty) ...[
                            SizedBox(
                              width: double.infinity,
                              height: 44,
                              child: FilledButton(
                                onPressed: _loading ? null : _save,
                                child: Text(_t('save_changes')),
                              ),
                            ),
                            const SizedBox(height: 12),
                          ],
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.logout),
                              onPressed: _logout,
                              label: Text(_t('sign_out')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Password & Security
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('security'),
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            !_isEmailVerified
                                ? _t('password_manage_requires_verified_email')
                                : _hasPassword
                                    ? _t('password_status_enabled')
                                    : _t('password_status_not_set'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton(
                              onPressed: _loading || !_isEmailVerified
                                  ? null
                                  : (_hasPassword
                                      ? _disablePassword
                                      : _enablePassword),
                              child: Text(_hasPassword
                                  ? _t('disable_password')
                                  : _t('enable_password')),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _t('danger_zone'),
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(color: Colors.red),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _t('delete_account_body'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.delete_forever_outlined),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                              onPressed: _confirmDeleteAccount,
                              label: Text(_t('delete_account')),
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
  }
}
