import 'package:flutter/material.dart';
import '../auth/tenant_auth_client.dart';
import '../auth/secure_token_store.dart';
import '../api_client.dart';
import '../core/widgets/brand_title.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key});

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final _api = AuthApi();
  final _store = SecureTokenStore();
  bool _loading = true;
  String? _error;
  Map<String, dynamic>? _me;

  // Editable fields (example: first_name, last_name)
  final _firstName = TextEditingController();
  final _lastName = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final me = await _api.me();
      _me = me;
      _firstName.text = (me['first_name'] ?? '').toString();
      _lastName.text = (me['last_name'] ?? '').toString();
    } catch (e) {
      _error = 'Failed to load profile';
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Profile updated')),
      );
    } catch (e) {
      setState(() => _error = 'Failed to update profile');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _logout() async {
    try {
      await _api.logout();
    } catch (_) {}
    await _store.clear();
    ApiClient().setAccessToken(null);
    if (!mounted) return;
    Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(section: 'Profile'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: _logout,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.red.withOpacity(.25)),
                      ),
                      child: Text(_error!, style: const TextStyle(color: Colors.red)),
                    ),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Account', style: Theme.of(context).textTheme.titleMedium),
                          const SizedBox(height: 12),
                          Text('Email', style: Theme.of(context).textTheme.bodySmall),
                          Text(_me?['email']?.toString() ?? '—', style: const TextStyle(fontWeight: FontWeight.w600)),
                          const SizedBox(height: 16),
                          TextField(
                            controller: _firstName,
                            decoration: const InputDecoration(
                              labelText: 'First name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _lastName,
                            decoration: const InputDecoration(
                              labelText: 'Last name',
                              border: OutlineInputBorder(),
                            ),
                          ),
                          const SizedBox(height: 16),
                          SizedBox(
                            width: double.infinity,
                            height: 44,
                            child: FilledButton(
                              onPressed: _loading ? null : _save,
                              child: const Text('Save changes'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    child: ListTile(
                      title: const Text('About'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).pushNamed('/about'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
