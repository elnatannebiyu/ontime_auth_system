import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/session_manager.dart';
import '../models/session.dart';

class SessionProvider extends StatefulWidget {
  final Widget child;
  final Widget? loadingWidget;
  final Widget? loginWidget;
  
  const SessionProvider({
    Key? key,
    required this.child,
    this.loadingWidget,
    this.loginWidget,
  }) : super(key: key);
  
  @override
  State<SessionProvider> createState() => _SessionProviderState();
  
  /// Get session manager from context
  static SessionManager of(BuildContext context) {
    return Provider.of<SessionManager>(context, listen: false);
  }
  
  /// Get current session from context
  static Session? sessionOf(BuildContext context) {
    return Provider.of<Session?>(context);
  }
  
  /// Listen to session changes
  static Session? watchSession(BuildContext context) {
    return context.watch<Session?>();
  }
}

class _SessionProviderState extends State<SessionProvider> with WidgetsBindingObserver {
  final SessionManager _sessionManager = SessionManager();
  bool _isInitialized = false;
  
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeSession();
  }
  
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
  
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Handle app lifecycle changes
    switch (state) {
      case AppLifecycleState.resumed:
        // App came to foreground - check session
        _checkSession();
        break;
      case AppLifecycleState.paused:
        // App went to background
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        break;
    }
  }
  
  Future<void> _initializeSession() async {
    try {
      await _sessionManager.initialize();
    } catch (e) {
      debugPrint('Failed to initialize session: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }
    }
  }
  
  Future<void> _checkSession() async {
    if (_sessionManager.isLoggedIn) {
      try {
        // Check if token needs refresh
        await _sessionManager.refreshToken();
      } catch (e) {
        debugPrint('Session refresh failed: $e');
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    if (!_isInitialized) {
      return widget.loadingWidget ?? 
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: CircularProgressIndicator(),
            ),
          ),
        );
    }
    
    return MultiProvider(
      providers: [
        Provider<SessionManager>.value(value: _sessionManager),
        StreamProvider<Session?>(
          create: (_) => _sessionManager.sessionStream,
          initialData: _sessionManager.currentSession,
        ),
      ],
      child: Consumer<Session?>(
        builder: (context, session, child) {
          // If login widget is provided and user is not logged in
          if (widget.loginWidget != null && session == null) {
            return widget.loginWidget!;
          }
          
          // Otherwise show the main app
          return widget.child;
        },
      ),
    );
  }
}

/// Extension methods for easier access
extension SessionContext on BuildContext {
  SessionManager get sessionManager => SessionProvider.of(this);
  Session? get session => SessionProvider.sessionOf(this);
  Session? get watchSession => SessionProvider.watchSession(this);
  bool get isLoggedIn => session != null;
}
