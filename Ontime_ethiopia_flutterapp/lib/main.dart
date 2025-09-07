import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'auth_repository.dart';
import 'auth/tenant_auth_client.dart';
import 'auth/login_page.dart';
import 'auth/register_page.dart';
import 'home/home_page.dart';
import 'core/theme/theme_controller.dart';
import 'core/theme/app_theme.dart';
import 'api_client.dart';
import 'auth/secure_token_store.dart';
import 'about/about_page.dart';
import 'profile/profile_page.dart';
import 'core/localization/l10n.dart';
import 'settings/settings_page.dart';
import 'settings/session_management_page.dart';
import 'settings/session_security_page.dart';
import 'auth/services/simple_session_manager.dart';
import 'features/forms/pages/dynamic_form_page.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Initialize enterprise auth client and token store
  final api = AuthApi();
  final tokenStore = SecureTokenStore();
  const tenantId = 'ontime'; // TODO: make this selectable
  final themeController = ThemeController();
  final localizationController = LocalizationController();

  // Initialize session manager
  final sessionManager = SimpleSessionManager();
  await sessionManager.initialize();

  // Ensure ApiClient has persistent cookies and restored access token before any requests
  await ApiClient().ensureInitialized();
  // Set tenant header early for all requests
  ApiClient().setTenant(tenantId);

  // Attempt to restore persisted token early
  final existingToken = await tokenStore.getAccess();
  if (existingToken != null && existingToken.isNotEmpty) {
    // ApiClient is a singleton; set token directly
    ApiClient().setAccessToken(existingToken);
  }

  await Future.wait([
    themeController.load(),
    localizationController.load(),
  ]);
  runApp(MyApp(
    api: api,
    tokenStore: tokenStore,
    tenantId: tenantId,
    themeController: themeController,
    localizationController: localizationController,
  ));
}

class MyApp extends StatefulWidget {
  final AuthApi? api;
  final TokenStore? tokenStore;
  final String? tenantId;
  final ThemeController? themeController;
  final LocalizationController? localizationController;

  const MyApp({
    super.key,
    this.api,
    this.tokenStore,
    this.tenantId,
    this.themeController,
    this.localizationController,
  });

  @override
  State<MyApp> createState() => _MyAppState();
}

class _MyAppState extends State<MyApp> {
  late final AuthApi api;
  late final TokenStore tokenStore;
  late final String tenantId;
  late final ThemeController themeController;
  late final LocalizationController localizationController;
  static final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();
  static final GlobalKey<ScaffoldMessengerState> _smKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    api = widget.api ?? AuthApi();
    tokenStore = widget.tokenStore ?? SecureTokenStore();
    tenantId = widget.tenantId ?? 'default';
    themeController = widget.themeController ?? ThemeController();
    localizationController =
        widget.localizationController ?? LocalizationController();
    // Start async loads if we created them here
    themeController.load();
    localizationController.load();

    // Register global force-logout handler so interceptor can redirect to login
    ApiClient().setForceLogoutHandler(() async {
      await tokenStore.clear();
      ApiClient().setAccessToken(null);
      _smKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Session expired. Please sign in again.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      _navKey.currentState?.pushNamedAndRemoveUntil('/login', (route) => false);
    });

    // Register notifier for offline/info messages from ApiClient
    ApiClient().setNotifier((message) {
      _smKey.currentState?.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([themeController, localizationController]),
      builder: (context, _) {
        return MaterialApp(
          title: 'Ontime Ethiopia - JWT Auth',
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: themeController.themeMode,
          navigatorKey: _navKey,
          scaffoldMessengerKey: _smKey,
          // Splash gate decides destination based on stored token
          initialRoute: '/',
          routes: {
            '/': (_) => SplashGate(
                api: api, tokenStore: tokenStore, tenantId: tenantId),
            '/login': (_) => LoginPage(
                  api: api,
                  tokenStore: tokenStore,
                  tenantId: tenantId,
                  themeController: themeController,
                ),
            '/register': (_) => RegisterPage(
                  api: api,
                  tokenStore: tokenStore,
                  tenantId: tenantId,
                  themeController: themeController,
                ),
            // New enterprise home screen
            '/home': (_) => HomePage(
                  api: api,
                  tokenStore: tokenStore,
                  tenantId: tenantId,
                  localizationController: localizationController,
                ),
            // Optional: expose the demo directly if needed
            '/demo': (_) => const AuthScreen(),
            // Settings route
            '/settings': (_) => SettingsPage(
                  themeController: themeController,
                  localizationController: localizationController,
                ),
            '/session-management': (_) => const SessionManagementPage(),
            '/session-security': (_) => const SessionSecurityPage(),
            '/about': (_) => const AboutPage(),
            '/profile': (_) => const ProfilePage(),
            // Dev routes for Dynamic Forms (Part 10/10b). Not linked in UI.
            '/dev/forms/login': (_) => const DynamicFormPage(action: 'login'),
            '/dev/forms/register': (_) => const DynamicFormPage(action: 'register'),
          },
        );
      },
    );
  }
}

class SplashGate extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;
  const SplashGate(
      {super.key,
      required this.api,
      required this.tokenStore,
      required this.tenantId});

  @override
  State<SplashGate> createState() => _SplashGateState();
}

class _SplashGateState extends State<SplashGate> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    try {
      widget.api.setTenant(widget.tenantId);
      // If token exists, validate it; otherwise go to login
      final access = await widget.tokenStore.getAccess();
      if (access == null || access.isEmpty) {
        if (!mounted) return;
        Navigator.of(context).pushReplacementNamed('/login');
        return;
      }
      // Validate token by calling me()
      await widget.api.me();
      if (!mounted) return;
      Navigator.of(context).pushReplacementNamed('/home');
    } catch (e) {
      // If offline or network error, keep tokens and go to home with an offline message
      if (e is DioException &&
          (e.type == DioExceptionType.connectionError || e.error is SocketException)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('You appear to be offline. Some actions may not work.'),
              behavior: SnackBarBehavior.floating,
            ),
          );
          Navigator.of(context).pushReplacementNamed('/home');
        }
        return;
      }

      // For other failures, show message and go to login (tokens may be invalid)
      await widget.tokenStore.clear();
      ApiClient().setAccessToken(null);
      if (!mounted) return;
      setState(() => _error = 'Session expired. Please sign in again.');
      await Future.delayed(const Duration(milliseconds: 300));
      Navigator.of(context).pushReplacementNamed('/login');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(_error ?? 'Loading...',
                style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      ),
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
  void initState() {
    super.initState();
    // Ensure all API calls include tenant header
    repo.setTenant('default');
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _status = 'Please enter email and password');
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

  Future<void> _register() async {
    if (_usernameController.text.isEmpty || _passwordController.text.isEmpty) {
      setState(() => _status = 'Please enter email and password');
      return;
    }

    setState(() => _loading = true);

    try {
      await repo.register(_usernameController.text, _passwordController.text);
      final me = await repo.me();
      setState(() {
        _userInfo = me;
        _status =
            'Registered & logged in as: ${me['username']}\nRoles: ${me['roles']}';
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _status = 'Registration failed: $e';
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
                        labelText: 'Email',
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
                OutlinedButton.icon(
                  onPressed: _loading || _userInfo != null ? null : _register,
                  icon: const Icon(Icons.person_add),
                  label: const Text('Register'),
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
