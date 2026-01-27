import 'package:flutter/material.dart';
import '../api_client.dart';
import 'package:video_player/video_player.dart';
import 'live_player_overlay_page.dart';
import '../core/navigation/route_stack_observer.dart';

class TvController extends ChangeNotifier {
  TvController._internal();
  static final TvController instance = TvController._internal();

  String? _currentSlug;
  bool _useUnifiedMiniPlayer = false;
  String? _currentTitle;
  bool _wasPlaying =
      false; // whether playback was active when user navigated away
  String? _viewSessionId;
  String? _playbackUrl;
  VideoPlayerController? _controller;
  bool _playing = false;
  bool _inFullPlayer = false;
  bool _initInFlight = false;
  Future<void>? _initFuture;
  String? _playbackError;

  String? get slug => _currentSlug;
  String? get title => _currentTitle;
  bool get hasCurrent => _currentSlug != null && _currentSlug!.isNotEmpty;
  bool get wasPlaying => _wasPlaying;
  String? get viewSessionId => _viewSessionId;
  String? get playbackUrl => _playbackUrl;
  VideoPlayerController? get controller => _controller;
  bool get isPlaying => _playing && (_controller?.value.isPlaying ?? false);
  bool get inFullPlayer => _inFullPlayer;
  bool get useUnifiedMiniPlayer => _useUnifiedMiniPlayer;
  bool get isInitialized => _controller?.value.isInitialized ?? false;
  bool get isBuffering => _controller?.value.isBuffering ?? false;
  bool get isIniting => _initInFlight;
  String? get playbackError => _playbackError;

  void setUseUnifiedMiniPlayer(bool v) {
    if (_useUnifiedMiniPlayer != v) {
      _useUnifiedMiniPlayer = v;
      notifyListeners();
    }
  }

  void setCurrent(
      {required String slug,
      required String title,
      String? sessionId,
      String? playbackUrl}) {
    if (slug.isEmpty) return;
    _currentSlug = slug;
    _currentTitle = title.isNotEmpty ? title : 'Live TV';
    _viewSessionId = sessionId;
    _playbackUrl = playbackUrl;
    notifyListeners();
  }

  void markWasPlaying(bool v) {
    if (_wasPlaying != v) {
      _wasPlaying = v;
      notifyListeners();
    }
  }

  void setInFullPlayer(bool v) {
    if (_inFullPlayer != v) {
      _inFullPlayer = v;
      notifyListeners();
    }
  }

  Future<void> startPlayback(
      {required String slug,
      required String title,
      required String url,
      String? sessionId}) async {
    // Replace radio if playing
    // Caller can pause/stop radio before invoking this if needed.
    _currentSlug = slug;
    _currentTitle = title.isNotEmpty ? title : 'Live TV';
    _playbackUrl = url;
    _viewSessionId = sessionId;
    // Serialize initialization to avoid concurrent controllers
    if (_initInFlight && _initFuture != null) {
      try {
        await _initFuture;
      } catch (_) {}
    }
    _initInFlight = true;
    _playbackError = null;
    notifyListeners();
    final init = _startOrReuse(url);
    _initFuture = init;
    try {
      await init;
      if (_controller != null && (_controller!.value.isInitialized)) {
        await _controller!.setLooping(true);
        try {
          await _controller!.play();
        } catch (_) {}
        _playing = true;
      } else {
        _playing = false;
      }
    } catch (e) {
      _playbackError = e.toString();
      _playing = false;
    } finally {
      _initInFlight = false;
      notifyListeners();
    }
  }

  Future<void> _startOrReuse(String url) async {
    if (_controller == null ||
        _playbackUrl != url ||
        !(_controller!.value.isInitialized)) {
      final old = _controller;
      _controller = null;
      notifyListeners();
      try {
        await old?.pause();
      } catch (_) {}
      try {
        await old?.dispose();
      } catch (_) {}
      final c = VideoPlayerController.networkUrl(Uri.parse(url));
      _controller = c;
      await c.initialize();
    }
  }

  Future<void> pausePlayback() async {
    try {
      await _controller?.pause();
    } catch (_) {}
    _playing = false;
    notifyListeners();
  }

  Future<void> resumePlayback() async {
    if (_controller == null || !(_controller!.value.isInitialized)) return;
    try {
      await _controller!.play();
    } catch (_) {}
    _playing = true;
    notifyListeners();
  }

  void clear() {
    _currentSlug = null;
    _currentTitle = null;
    _wasPlaying = false;
    _viewSessionId = null;
    _playbackUrl = null;
    _useUnifiedMiniPlayer = false;
    notifyListeners();
  }

  Future<void> stop() async {
    final slug = _currentSlug;
    final sid = _viewSessionId;
    try {
      if (slug != null && slug.isNotEmpty && sid != null && sid.isNotEmpty) {
        await ApiClient().post('/live/$slug/listen/stop/', data: {
          'session_id': sid,
        });
      }
    } catch (_) {}
    try {
      await _controller?.pause();
    } catch (_) {}
    try {
      await _controller?.dispose();
    } catch (_) {}
    _controller = null;
    _playing = false;
    _playbackUrl = null;
    _playbackError = null;
    _viewSessionId = null;
    _currentSlug = null;
    _currentTitle = null;
    _wasPlaying = false;
    _useUnifiedMiniPlayer = false;
    notifyListeners();
  }
}

class MiniVideoBar extends StatefulWidget {
  const MiniVideoBar({super.key});

  @override
  State<MiniVideoBar> createState() => _MiniVideoBarState();
}

class _MiniVideoBarState extends State<MiniVideoBar> {
  final tv = TvController.instance;

  @override
  void initState() {
    super.initState();
    tv.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    tv.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!tv.hasCurrent) return const SizedBox.shrink();

    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.live_tv, size: 20),
              const SizedBox(width: 8),
              // Buffering/initializing indicator
              if (tv.isIniting || tv.isBuffering) ...[
                const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
              ],
              // Tappable title to open full player
              Expanded(
                child: InkWell(
                  onTap: _openFull,
                  child: Text(
                    tv.title?.trim().isNotEmpty == true
                        ? tv.title!.trim()
                        : 'Live TV',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              // Open full player
              Semantics(
                button: true,
                label: 'Expand video player',
                child: IconButton(
                  tooltip: 'Expand',
                  icon: const Icon(Icons.open_in_full),
                  onPressed: _openFull,
                ),
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () {
                  tv.stop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openFull() {
    final slug = tv.slug;
    if (slug == null || slug.isEmpty) return;

    final nav = Navigator.of(context, rootNavigator: true);
    final target = '/live/overlay/$slug';
    if (appRouteStackObserver.containsName(target)) {
      nav.popUntil((route) => route.settings.name == target);
      return;
    }
    nav.push(
      PageRouteBuilder(
        settings: RouteSettings(name: target),
        pageBuilder: (_, __, ___) => LivePlayerOverlayPage(slug: slug),
        transitionDuration: const Duration(milliseconds: 280),
        reverseTransitionDuration: const Duration(milliseconds: 220),
        transitionsBuilder: (_, animation, __, child) {
          const begin = Offset(0.0, 1.0);
          const end = Offset.zero;
          final tween = Tween(begin: begin, end: end)
              .chain(CurveTween(curve: Curves.easeOutCubic));
          return SlideTransition(
              position: animation.drive(tween), child: child);
        },
      ),
    );
  }
}
