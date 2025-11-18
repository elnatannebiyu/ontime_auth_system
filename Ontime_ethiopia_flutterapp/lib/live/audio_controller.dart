// ignore_for_file: prefer_final_fields

import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:math';
import 'dart:io' show Platform;
import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import '../api_client.dart';

class AudioController extends ChangeNotifier {
  AudioController._internal();
  static final AudioController instance = AudioController._internal();

  final AudioPlayer _player = AudioPlayer();
  String? _currentTitle;
  String? _currentSlug;
  String? _currentUrl;
  bool _sessionReady = false;
  String _listenSessionId = _genSessionId();
  Timer? _hbTimer;
  StreamSubscription<PlayerState>? _psSub;
  StreamSubscription<PlaybackEvent>? _evSub;

  AudioPlayer get player => _player;
  String? get title => _currentTitle;
  String? get slug => _currentSlug;
  String? get url => _currentUrl;
  bool get isActive => _currentUrl != null;

  Future<void> playRadioBySlug(String slug) async {
    await _ensureSession();
    // If switching stations, stop previous session reporting
    final prevSlug = _currentSlug;
    if (prevSlug != null && prevSlug != slug) {
      debugPrint('[AudioController] switching station: $prevSlug -> $slug');
      await _sendStop(prevSlug);
      _cancelHeartbeat();
    }
    _currentSlug = slug;
    // fetch radio detail to get stream_url
    debugPrint('[AudioController] fetching radio detail for $slug');
    final res = await ApiClient().get('/live/radio/$slug/');
    final m = Map<String, dynamic>.from(res.data as Map);
    final primary =
        (m['stream_url'] ?? m['url_resolved'] ?? m['url'] ?? '').toString();
    final backup = (m['backup_stream_url'] ?? '').toString();
    final name = (m['name'] ?? slug).toString();
    if (primary.isEmpty && backup.isEmpty) {
      throw Exception('No stream URL');
    }
    _currentTitle = name;
    // Try primary then backup with timeouts
    Future<void> setAndPlay(String u) async {
      _currentUrl = u;
      try {
        final t0 = DateTime.now();
        debugPrint('[AudioController] setAudioSource -> $u');
        final hdrs = <String, String>{
          // On iOS, AVPlayer cannot parse ICY metadata in-band; disable it
          'Icy-MetaData': Platform.isIOS ? '0' : '1',
          'User-Agent': 'ontime-app/1.0',
        };
        // If requesting our proxy, attach auth/tenant so Django allows it
        if (u.startsWith(kApiBase)) {
          final token = ApiClient().getAccessToken();
          final tenant = ApiClient().tenant;
          if (token != null && token.isNotEmpty) {
            hdrs['Authorization'] = 'Bearer $token';
          }
          if (tenant != null && tenant.isNotEmpty) {
            hdrs['X-Tenant-Id'] = tenant;
          }
        }
        final src = AudioSource.uri(Uri.parse(u), headers: hdrs);
        await _player.setAudioSource(src).timeout(const Duration(seconds: 8));
        debugPrint(
            '[AudioController] setAudioSource OK in ${DateTime.now().difference(t0).inMilliseconds}ms');
        // Make the MiniAudioBar appear as soon as we have a valid source
        notifyListeners();
      } on TimeoutException {
        debugPrint('[AudioController] setAudioSource TIMEOUT');
        rethrow;
      }
      // Start playback and consider it successful as soon as the player reports
      // playing/ready/buffering. Some streams output audio but the Future may
      // not resolve quickly; avoid false negatives.
      final t1 = DateTime.now();
      debugPrint('[AudioController] play()');
      await _player.play();
      var ok = false;
      for (int i = 0; i < 14; i++) {
        // ~7s window
        final st = _player.playerState;
        if (st.playing ||
            st.processingState == ProcessingState.ready ||
            st.processingState == ProcessingState.buffering) {
          ok = true;
          break;
        }
        await Future.delayed(const Duration(milliseconds: 500));
      }
      if (ok || _player.playing) {
        debugPrint(
            '[AudioController] play() OK in ${DateTime.now().difference(t1).inMilliseconds}ms');
      } else {
        debugPrint('[AudioController] play() TIMEOUT');
        throw TimeoutException('play did not start in time');
      }
    }

    // Build candidate URLs with common Icecast/Shoutcast variants
    List<String> candidates0() {
      String norm(String s) => s.trim();
      final cands = <String>[];
      // Always try backend proxy first; it normalizes headers/Range and avoids client quirks
      final baseApi =
          kApiBase; // e.g., http://localhost:8000 or http://192.168.x.x:8000
      final t = ApiClient().tenant ?? 'ontime';
      cands.add('$baseApi/api/live/radio/$slug/stream/?tenant=$t');
      if (primary.isNotEmpty) cands.add(norm(primary));
      if (backup.isNotEmpty && backup != primary) cands.add(norm(backup));
      // For roots or missing mountpoints, try common aliases (avoid exploding attempts for token hosts)
      bool isZeno(String u) => u.contains('zeno.fm') || u.contains('stream-');
      final tokenHost = isZeno(primary) || isZeno(backup);
      if (!tokenHost) {
        for (final base in [primary, backup]) {
          if (base.isEmpty) continue;
          final b =
              base.endsWith('/') ? base.substring(0, base.length - 1) : base;
          cands.add('$b/live');
          cands.add('$b/live.mp3');
          cands.add('$b/stream');
          cands.add('$b/stream.mp3');
          cands.add('$b/;stream/1');
          cands.add('$b/;?type=http');
          cands.add('$b/;');
        }
      } else {
        // Tokenized streams usually only work with exact URL; try minimal safe suffixes
        for (final base in [primary, backup]) {
          if (base.isEmpty) continue;
          final b =
              base.endsWith('/') ? base.substring(0, base.length - 1) : base;
          cands.add('$b/live');
          cands.add('$b/live.mp3');
        }
      }
      // Deduplicate while preserving order
      final seen = <String>{};
      final out = <String>[];
      for (final u in cands) {
        if (u.isEmpty) continue;
        if (seen.add(u)) out.add(u);
      }
      return out;
    }

    final candidates = candidates0();
    Exception? lastErr;
    for (var i = 0; i < candidates.length; i++) {
      final u = candidates[i];
      try {
        debugPrint(
            '[AudioController] attempt ${i + 1}/${candidates.length}: $u');
        await setAndPlay(u);
        lastErr = null;
        break;
      } on TimeoutException catch (e) {
        lastErr = e;
        try {
          await _player.stop();
        } catch (_) {}
        debugPrint('[AudioController] attempt ${i + 1} TIMEOUT');
      } catch (e) {
        // Other errors: proceed to next
        lastErr = Exception(e.toString());
        try {
          await _player.stop();
        } catch (_) {}
        debugPrint('[AudioController] attempt ${i + 1} failed: $e');
      }
    }
    if (lastErr != null) {
      _currentUrl = null;
      _currentTitle = null;
      _currentSlug = null;
      throw lastErr;
    }
    // Report start and begin heartbeat
    await _sendStart(slug);
    _startHeartbeat(slug);
    _attachPlayerLogging();
    notifyListeners();
  }

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    try {
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration.music());
      _sessionReady = true;
    } catch (_) {
      // Ignore, best-effort configuration
      _sessionReady = true;
    }
  }

  Future<void> pause() async {
    await _player.pause();
    debugPrint('[AudioController] pause()');
    notifyListeners();
  }

  Future<void> pauseForShorts() async {
    await pause();
  }

  Future<void> play() async {
    await _player.play();
    debugPrint('[AudioController] resume play()');
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    final slug = _currentSlug;
    if (slug != null) {
      await _sendStop(slug);
    }
    _cancelHeartbeat();
    _detachPlayerLogging();
    _currentUrl = null;
    _currentTitle = null;
    _currentSlug = null;
    notifyListeners();
  }

  @override
  void dispose() {
    try {
      _psSub?.cancel();
    } catch (_) {}
    try {
      _evSub?.cancel();
    } catch (_) {}
    _cancelHeartbeat();
    _player.dispose();
    super.dispose();
  }

  // --- Listen tracking helpers ---
  static String _genSessionId() {
    final r = Random();
    final t = DateTime.now().millisecondsSinceEpoch;
    final a = r.nextInt(1 << 32);
    final b = r.nextInt(1 << 32);
    return 'r${t.toRadixString(36)}-${a.toRadixString(36)}${b.toRadixString(36)}';
  }

  Future<void> _sendStart(String slug) async {
    try {
      debugPrint(
          '[AudioController] listen START -> $slug session=$_listenSessionId');
      await ApiClient().post('/live/radio/$slug/listen/start/', data: {
        'session_id': _listenSessionId,
      });
    } catch (_) {}
  }

  Future<void> _sendHeartbeat(String slug) async {
    try {
      debugPrint(
          '[AudioController] listen HEARTBEAT -> $slug session=$_listenSessionId');
      await ApiClient().post('/live/radio/$slug/listen/heartbeat/', data: {
        'session_id': _listenSessionId,
      });
    } catch (_) {}
  }

  Future<void> _sendStop(String slug) async {
    try {
      debugPrint(
          '[AudioController] listen STOP -> $slug session=$_listenSessionId');
      await ApiClient().post('/live/radio/$slug/listen/stop/', data: {
        'session_id': _listenSessionId,
      });
    } catch (_) {}
  }

  void _startHeartbeat(String slug) {
    _cancelHeartbeat();
    _hbTimer = Timer.periodic(const Duration(seconds: 45), (_) async {
      // Only heartbeat if still on the same slug
      if (_currentSlug == slug) {
        await _sendHeartbeat(slug);
      }
    });
  }

  void _cancelHeartbeat() {
    try {
      _hbTimer?.cancel();
    } catch (_) {}
    _hbTimer = null;
  }

  void _attachPlayerLogging() {
    _detachPlayerLogging();
    _psSub = _player.playerStateStream.listen((s) {
      debugPrint(
          '[AudioController] state: playing=${s.playing} processing=${s.processingState}');
    }, onError: (e) {
      debugPrint('[AudioController] playerStateStream error: $e');
    });
    _evSub = _player.playbackEventStream.listen((e) {
      debugPrint(
          '[AudioController] event: buf=${e.bufferedPosition} dur=${e.duration}');
    }, onError: (e) {
      debugPrint('[AudioController] playbackEventStream error: $e');
    });
  }

  void _detachPlayerLogging() {
    try {
      _psSub?.cancel();
    } catch (_) {}
    try {
      _evSub?.cancel();
    } catch (_) {}
    _psSub = null;
    _evSub = null;
  }
}

class MiniAudioBar extends StatefulWidget {
  const MiniAudioBar({super.key});

  @override
  State<MiniAudioBar> createState() => _MiniAudioBarState();
}

class _MiniAudioBarState extends State<MiniAudioBar> {
  final ctrl = AudioController.instance;

  @override
  void initState() {
    super.initState();
    ctrl.addListener(_onChanged);
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ctrl.removeListener(_onChanged);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ctrl.isActive) return const SizedBox.shrink();

    return Material(
      elevation: 6,
      color: Theme.of(context).colorScheme.surface,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              const Icon(Icons.radio, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Now playing ${ctrl.title ?? 'Radio'}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
              ),
              StreamBuilder<PlayerState>(
                stream: ctrl.player.playerStateStream,
                builder: (context, snap) {
                  final playing = snap.data?.playing ?? ctrl.player.playing;
                  return IconButton(
                    tooltip: playing ? 'Pause' : 'Play',
                    icon:
                        Icon(playing ? Icons.pause_circle : Icons.play_circle),
                    iconSize: 30,
                    onPressed: () async {
                      if (playing) {
                        await ctrl.pause();
                      } else {
                        await ctrl.play();
                      }
                    },
                  );
                },
              ),
              IconButton(
                tooltip: 'Close',
                icon: const Icon(Icons.close),
                onPressed: () => ctrl.stop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
