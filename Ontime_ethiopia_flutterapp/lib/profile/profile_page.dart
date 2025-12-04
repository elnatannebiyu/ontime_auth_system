import 'dart:async';

import 'package:flutter/material.dart';
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

  Future<void> _requestEmailVerification() async {
    if (_me == null || _isEmailVerified) return;
    try {
      await ApiClient().post('/me/request-email-verification/', data: {});
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('verification_email_sent')),
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('verification_email_failed')),
        ),
      );
    }
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
                                            onPressed: _loading
                                                ? null
                                                : _requestEmailVerification,
                                            child: Text(_t('verify_now')),
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
