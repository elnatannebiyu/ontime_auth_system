import 'package:flutter/material.dart';
import 'auth_repository.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ontime Ethiopia - JWT Auth',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const AuthScreen(),
    );
  }
}

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final repo = AuthRepository();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  String _status = 'Not logged in';
  bool _loading = false;
  Map<String, dynamic>? _userInfo;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _status = 'Please enter username and password');
      return;
    }

    setState(() => _loading = true);

    try {
      await repo.login(_usernameController.text, _passwordController.text);
      final me = await repo.me();
      setState(() {
        _userInfo = me;
        _status =
            'Logged in as: ${me['username']}\nRoles: ${me['roles']}\nPermissions: ${me['permissions']?.take(3).join(', ')}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Login failed: $e';
        _loading = false;
        _userInfo = null;
      });
    }
  }

  Future<void> _testAdminEndpoint() async {
    setState(() => _loading = true);

    try {
      final res = await repo.adminOnly();
      setState(() {
        _status = 'Admin endpoint response: ${res['message']}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Admin endpoint failed: $e';
        _loading = false;
      });
    }
  }

  Future<void> _logout() async {
    setState(() => _loading = true);

    try {
      await repo.logout();
      setState(() {
        _status = 'Logged out successfully';
        _userInfo = null;
        _loading = false;
        _usernameController.clear();
        _passwordController.clear();
      });
    } catch (e) {
      setState(() {
        _status = 'Logout failed: $e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: const Text('Ontime Ethiopia - JWT Auth Demo'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.person),
                      ),
                      enabled: !_loading && _userInfo == null,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _passwordController,
                      obscureText: true,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      enabled: !_loading && _userInfo == null,
                      onSubmitted: (_) => _userInfo == null ? _login() : null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                FilledButton.icon(
                  onPressed: _loading || _userInfo != null ? null : _login,
                  icon: const Icon(Icons.login),
                  label: const Text('Login'),
                ),
                FilledButton.tonalIcon(
                  onPressed:
                      _loading || _userInfo == null ? null : _testAdminEndpoint,
                  icon: const Icon(Icons.admin_panel_settings),
                  label: const Text('Test Admin'),
                ),
                OutlinedButton.icon(
                  onPressed: _loading || _userInfo == null ? null : _logout,
                  icon: const Icon(Icons.logout),
                  label: const Text('Logout'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else
              Card(
                color: _userInfo != null
                    ? Theme.of(context).colorScheme.primaryContainer
                    : Theme.of(context).colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            _userInfo != null
                                ? Icons.check_circle
                                : Icons.info_outline,
                            color: _userInfo != null
                                ? Theme.of(context).colorScheme.primary
                                : Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Status',
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                  fontWeight: FontWeight.bold,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _status,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            Card(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: Padding(
                padding: const EdgeInsets.all(12.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text(
                      '📱 Mobile Development Notes:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    SizedBox(height: 8),
                    Text('• Android emulator: uses 10.0.2.2:8000'),
                    Text('• iOS simulator: uses localhost:8000'),
                    Text('• HttpOnly cookies handled automatically'),
                    Text('• No CORS needed for mobile apps'),
                    Text('• Use HTTPS in production'),
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
