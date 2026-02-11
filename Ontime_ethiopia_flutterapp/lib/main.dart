// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'dart:io';
import 'auth_repository.dart';
import 'auth/tenant_auth_client.dart';
import 'auth/login_page.dart';
import 'auth/register_page.dart';
import 'auth/forgot_password_page.dart';
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
import 'live/live_page.dart';
import 'audio/mini_audio_bar.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/version/version_gate.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'settings/notification_inbox_page.dart';
import 'channels/player/channel_mini_player.dart';
import 'channels/player/channel_mini_player_manager.dart';
import 'channels/playlist_detail_page_dummy.dart';
import 'core/navigation/route_stack_observer.dart';
import 'features/series/mini_player/series_mini_player.dart';
import 'package:provider/provider.dart';
import 'live/audio_controller.dart';
import 'audio/app_lifecycle_signal.dart';

// Global route observer to allow RouteAware widgets to pause/resume media
final RouteObserver<ModalRoute<void>> appRouteObserver =
    RouteObserver<ModalRoute<void>>();
// Public navigator key to allow navigation from global widgets (e.g., mini player)
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey<NavigatorState>();

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  // TODO: handle background message data if needed
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLifecycleSignal.I.start();
  // NOTE: Firebase was temporarily disabled for local iOS testing.
  // Now that the iOS Firebase project (GoogleService-Info.plist) is configured,
  // we initialize Firebase and register the background message handler.
  try {
    debugPrint('[firebase] Initializing default app...');
    await Firebase.initializeApp();
    debugPrint('[firebase] Initialization succeeded');
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
  } catch (e, st) {
    debugPrint('[firebase] Initialization FAILED: $e');
    debugPrint('[firebase] Stack: $st');
    // Do not crash app if Firebase init fails; Google/FCM on iOS will remain disabled.
  }
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
  late final AudioController _audioController;
  static final GlobalKey<ScaffoldMessengerState> _smKey =
      GlobalKey<ScaffoldMessengerState>();
  bool _updateDialogShown = false;
  String? _pendingUpdateMsg;
  String? _pendingUpdateUrl;

  Future<void> _openStoreLinkWithFallback(BuildContext ctx, String url) async {
    try {
      final uri = Uri.parse(url);
      // 1) Try external application
      if (await canLaunchUrl(uri)) {
        final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (ok) return;
      }
      // 2) Try in-app webview
      final okWeb = await launchUrl(uri, mode: LaunchMode.inAppWebView);
      if (okWeb) return;
    } catch (_) {}
    // 3) Last resort: show the URL and allow copy
    if (!mounted) return;
    showDialog(
      context: ctx,
      builder: (_) => AlertDialog(
        title: Text(localizationController.t('open_link_manually')),
        content: SelectableText(url),
        actions: [
          TextButton(
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: url));
                Navigator.of(ctx).pop();
                ScaffoldMessenger.of(ctx).showSnackBar(
                  SnackBar(
                      content: Text(localizationController.t('link_copied'))),
                );
              } catch (_) {
                Navigator.of(ctx).pop();
              }
            },
            child: Text(localizationController.t('copy')),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(localizationController.t('close_dialog')),
          ),
        ],
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    try {
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    } catch (_) {}
    api = widget.api ?? AuthApi();
    tokenStore = widget.tokenStore ?? SecureTokenStore();
    tenantId = widget.tenantId ?? 'default';
    themeController = widget.themeController ?? ThemeController();
    localizationController =
        widget.localizationController ?? LocalizationController();
    _audioController = AudioController();
    try {
      SimpleSessionManager().registerAudioController(_audioController);
    } catch (_) {}
    ChannelMiniPlayerManager.I.setExpandHandler((now) {
      final playlistId = (now.playlistId ?? '').isNotEmpty
          ? now.playlistId
          : ChannelMiniPlayerManager.I.lastPlaylistId;
      if (playlistId == null || playlistId.isEmpty) return;
      final nav = appNavigatorKey.currentState;
      debugPrint(
          '[ChannelMiniPlayer] expand requested playlistId=$playlistId navReady=${nav != null}');
      if (nav == null) return;
      final title = now.playlistTitle ??
          ChannelMiniPlayerManager.I.lastPlaylistTitle ??
          now.title;
      final routeName = '/playlist/$playlistId';
      if (kDebugMode) {
        debugPrint(
            '[MiniExpand] route=$routeName top=${appRouteStackObserver.top} inStack=${appRouteStackObserver.containsName(routeName)}');
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final currentNav = appNavigatorKey.currentState;
        if (currentNav == null) return;
        if (appRouteStackObserver.top == routeName) {
          ChannelMiniPlayerManager.I.setPendingOpenFromMini(playlistId);
          ChannelMiniPlayerManager.I.setSuppressed(true);
          return;
        }
        if (appRouteStackObserver.containsName(routeName)) {
          ChannelMiniPlayerManager.I.setPendingOpenFromMini(playlistId);
          ChannelMiniPlayerManager.I.setSuppressed(true);
          currentNav.popUntil((route) => route.settings.name == routeName);
        } else {
          currentNav
              .push(
            MaterialPageRoute(
              settings: RouteSettings(name: routeName),
              builder: (_) => PlaylistDetailPageDummy(
                playlistId: playlistId,
                title: title,
                origin: PlaylistOpenOrigin.maximizeFromMini,
              ),
            ),
          )
              .then((_) {
            ChannelMiniPlayerManager.I.setSuppressed(false);
          });
        }
      });
    });
    // Start async loads if we created them here
    themeController.load();
    localizationController.load();

    // Register global force-logout handler so interceptor can redirect to login
    ApiClient().setForceLogoutHandler(() async {
      // Use session manager to ensure social provider sign-out (e.g., Google)
      try {
        await SimpleSessionManager().logout();
      } catch (_) {
        // Fallback clearing if needed
        await tokenStore.clear();
        ApiClient().setAccessToken(null);
      }
      _smKey.currentState?.showSnackBar(
        SnackBar(
          content: Text(localizationController.t('session_expired')),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
      appNavigatorKey.currentState
          ?.pushNamedAndRemoveUntil('/login', (route) => false);
    });

    // Register notifier for offline/info messages from ApiClient
    ApiClient().setNotifier((message) {
      _smKey.currentState?.showSnackBar(
        SnackBar(content: Text(message), behavior: SnackBarBehavior.floating),
      );
    });

    // Show a blocking modal when the backend enforces an app update (HTTP 426)
    ApiClient().setUpdateRequiredHandler((message, storeUrl) async {
      // Do not navigate here; ApiClient's force-logout handler already sends user to /login
      final ctx = appNavigatorKey.currentContext;
      if (ctx == null) {
        // Cache and try again after the next frame when context becomes available
        _pendingUpdateMsg = message;
        _pendingUpdateUrl = storeUrl;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          final ctx2 = appNavigatorKey.currentContext;
          if (ctx2 != null &&
              !_updateDialogShown &&
              _pendingUpdateMsg != null) {
            _showUpdateDialog(ctx2, _pendingUpdateMsg!, _pendingUpdateUrl);
            _pendingUpdateMsg = null;
            _pendingUpdateUrl = null;
          }
        });
        return;
      }
      if (_updateDialogShown) return;
      _showUpdateDialog(ctx, message, storeUrl);
    });

    // Initialize app-level checks (version gate, pending update dialog).
    // NOTE: FCM / FirebaseMessaging integration is temporarily disabled for
    // local iOS testing until Firebase is fully configured for this app.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = appNavigatorKey.currentContext;
      // If a pending 426 was cached before context existed, show it now
      if (ctx != null && !_updateDialogShown && _pendingUpdateMsg != null) {
        _showUpdateDialog(ctx, _pendingUpdateMsg!, _pendingUpdateUrl);
        _pendingUpdateMsg = null;
        _pendingUpdateUrl = null;
      }
      if (ctx != null && !_updateDialogShown) {
        VersionGate.checkAndPrompt(ctx);
      }

      // FCMManager / FirebaseMessaging hooks removed temporarily.
      // Re-enable these when Firebase.initializeApp is configured for iOS.
      // FcmManager().initialize(context: appNavigatorKey.currentContext);
      // FirebaseMessaging.instance.getInitialMessage()... etc.
    });
  }

  void _showUpdateDialog(BuildContext ctx, String message, String? storeUrl) {
    _updateDialogShown = true;
    showDialog(
      context: ctx,
      barrierDismissible: false,
      builder: (_) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          title: Text(localizationController.t('update_required_title')),
          content: Text(
            message.isNotEmpty
                ? message
                : localizationController.t('update_required_body'),
          ),
          actions: [
            FilledButton(
              onPressed: (storeUrl == null || storeUrl.isEmpty)
                  ? null
                  : () async {
                      final ctx2 = appNavigatorKey.currentContext ?? ctx;
                      await _openStoreLinkWithFallback(ctx2, storeUrl);
                    },
              style: ButtonStyle(
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (states.contains(WidgetState.disabled)) {
                    return Colors.grey.shade400;
                  }
                  return null;
                }),
              ),
              child: Text(localizationController.t('update_cta')),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AudioController>.value(
      value: _audioController,
      child: AnimatedBuilder(
        animation: Listenable.merge([themeController, localizationController]),
        builder: (context, _) {
          return MaterialApp(
            title: 'Ontime Ethiopia - JWT Auth',
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: themeController.themeMode,
            navigatorKey: appNavigatorKey,
            scaffoldMessengerKey: _smKey,
            navigatorObservers: [appRouteObserver, appRouteStackObserver],
            builder: (context, child) {
              final safeChild = SafeArea(
                child: child ?? const SizedBox.shrink(),
              );
              return Overlay(
                initialEntries: [
                  OverlayEntry(builder: (_) => safeChild),
                  OverlayEntry(
                    builder: (_) => ValueListenableBuilder<bool>(
                      valueListenable:
                          ChannelMiniPlayerManager.I.hideGlobalBottomOverlays,
                      builder: (context, hide, __) {
                        if (hide) return const SizedBox.shrink();
                        return const ChannelMiniPlayer();
                      },
                    ),
                  ),
                  OverlayEntry(
                    builder: (ctx) => ValueListenableBuilder<bool>(
                      valueListenable:
                          ChannelMiniPlayerManager.I.hideGlobalBottomOverlays,
                      builder: (context, hide, __) {
                        if (hide) return const SizedBox.shrink();
                        return Positioned(
                          left: 0,
                          right: 0,
                          bottom: MediaQuery.of(ctx).padding.bottom,
                          child: const SeriesMiniPlayer(),
                        );
                      },
                    ),
                  ),
                  OverlayEntry(
                    builder: (ctx) => ValueListenableBuilder<bool>(
                      valueListenable:
                          ChannelMiniPlayerManager.I.hideGlobalBottomOverlays,
                      builder: (context, hide, __) {
                        return Consumer<AudioController>(
                          builder: (context, audio, _) {
                            // If audio is active, always show the radio mini-bar.
                            // Fullscreen overlays may hide global bottom overlays,
                            // but radio playback needs a visible controller.
                            if (hide && !audio.isActive) {
                              return const SizedBox.shrink();
                            }
                            return Positioned(
                              left: 0,
                              right: 0,
                              bottom: MediaQuery.of(ctx).padding.bottom,
                              child: const MiniAudioBar(),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              );
            },
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
                    localizationController: localizationController,
                  ),
              '/forgot-password': (_) => ForgotPasswordPage(
                    localizationController: localizationController,
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
              '/inbox': (_) => const NotificationInboxPage(),
              '/session-management': (_) => const SessionManagementPage(),
              '/session-security': (_) => const SessionSecurityPage(),
              '/about': (_) => const AboutPage(),
              '/profile': (_) => ProfilePage(
                    localizationController: localizationController,
                  ),
              '/live': (_) => const LivePage(),
              // Dev routes for Dynamic Forms (Part 10/10b). Not linked in UI.
              '/dev/forms/login': (_) => const DynamicFormPage(action: 'login'),
              '/dev/forms/register': (_) =>
                  const DynamicFormPage(action: 'register'),
            },
          );
        },
      ),
    );
  }

  @override
  void dispose() {
    try {
      _audioController.dispose();
    } catch (_) {}
    super.dispose();
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
    } on DioException catch (e) {
      // If offline or network error, keep tokens and go to home with an offline message
      if (e.type == DioExceptionType.connectionError ||
          e.error is SocketException) {
        if (mounted) {
          Navigator.of(context).pushReplacementNamed('/home');
        }
        return;
      }
      // For other auth failures, clear and go to login
      await widget.tokenStore.clear();
      ApiClient().setAccessToken(null);
      if (!mounted) return;
      setState(() => _error = 'Session expired. Please sign in again.');
      await Future.delayed(const Duration(milliseconds: 300));
      Navigator.of(context).pushReplacementNamed('/login');
    } catch (_) {
      // Any unexpected failure: clear and go to login
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
      // Use the centralized session manager so social providers are signed out
      await SimpleSessionManager().logout();
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
