import 'package:flutter/material.dart';
import '../auth/tenant_auth_client.dart';
import '../channels/channels_page.dart';

class HomePage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;

  const HomePage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      widget.api.setTenant(widget.tenantId);
      final me = await widget.api.me();
      setState(() {
        _me = me;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load profile';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    setState(() => _loading = true);
    try {
      await widget.api.logout();
      await widget.tokenStore.clear();
      if (!mounted) return;
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
    } catch (e) {
      setState(() {
        _error = 'Logout failed';
      });
    } finally {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home'),
        actions: [
          IconButton(
            onPressed: _loading ? null : _load,
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _loading
                ? null
                : () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const ChannelsPage(tenantId: 'ontime'),
                      ),
                    );
                    // On return from Channels, ensure Home API is back on default tenant
                    widget.api.setTenant(widget.tenantId);
                  },
            icon: const Icon(Icons.video_library),
            label: const Text('Channels'),
          ),
          const SizedBox(width: 8),
          TextButton.icon(
            onPressed: _loading ? null : _logout,
            icon: const Icon(Icons.logout),
            label: const Text('Logout'),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const CircularProgressIndicator()
                : _error != null
                    ? Text(_error!, style: const TextStyle(color: Colors.red))
                    : _me == null
                        ? const Text('No data')
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                  'Welcome, ${_me!['username'] ?? _me!['email']}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .headlineSmall),
                              const SizedBox(height: 8),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Your profile',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      Text('Email: ${_me!['email']}'),
                                      Text('Global roles: ${_me!['roles']}'),
                                      Text(
                                          'Tenant roles: ${_me!['tenant_roles']}'),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),
                              Card(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Quick tips',
                                          style: TextStyle(
                                              fontWeight: FontWeight.bold)),
                                      const SizedBox(height: 8),
                                      const Text(
                                          '• Tenant header is set automatically.'),
                                      const Text(
                                          '• Use the refresh button to reload profile.'),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
          ),
        ),
      ),
    );
  }
}
