// ignore_for_file: prefer_final_fields

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../api_client.dart';
import '../audio/audio_player_service.dart';
import 'package:ontime_ethiopia_flutterapp/audio/listen_tracker.dart';
import 'package:ontime_ethiopia_flutterapp/audio/radio_stream_resolver.dart';
import 'package:ontime_ethiopia_flutterapp/audio/radio_audio_service.dart';
import 'package:ontime_ethiopia_flutterapp/audio/app_lifecycle_signal.dart';
import 'package:ontime_ethiopia_flutterapp/audio/radio_start_attempts.dart';
import '../core/localization/l10n.dart' as l10n;

enum AudioStatus {
  idle,
  resolving,
  loading,
  buffering,
  playing,
  paused,
  error,
  stopped,
}

class AudioController extends ChangeNotifier {
  AudioController() {
    _lifecycleSub = AppLifecycleSignal.I.stream.listen((s) async {
      if (s == AppLifecycleState.detached) {
        try {
          await stop();
        } catch (_) {}
        return;
      }
      if (s == AppLifecycleState.paused || s == AppLifecycleState.inactive) {
        if (hasSource || _playerService.isPlaying) {
          try {
            await stop();
          } catch (_) {}
        }
        return;
      }
      if (s == AppLifecycleState.resumed) {
        if (_pausedBySystem && hasSource && !_playerService.isPlaying) {
          try {
            await _playerService.play();
            _pausedBySystem = false;
            notifyListeners();
          } catch (_) {}
        }
      }
    });
  }

  final AudioPlayerService _playerService = AudioPlayerService();
  late final ListenTracker _listenTracker = ListenTracker();
  AudioStatus status = AudioStatus.idle;
  String? errorMessage;
  String? _currentTitle;
  String? _currentSlug;
  String? _currentUrl;
  StreamSubscription<PlayerState>? _statusSub;
  int _opToken = 0;
  Timer? _bufferingTimeout;
  static const Duration _bufferingTimeoutDuration = Duration(seconds: 15);
  StreamSubscription<AppLifecycleState>? _lifecycleSub;
  bool _pausedBySystem = false;

  Stream<PlayerState> get playerStateStream => _playerService.playerStateStream;
  bool get isPlaying => _playerService.isPlaying;
  Stream<double> get volumeStream => _playerService.volumeStream;
  double get volume => _playerService.volume;
  Future<void> setVolume(double v) => _playerService.setVolume(v);
  bool get hasSource => _playerService.hasSource;
  String? get title => _currentTitle;
  String? get slug => _currentSlug;
  String? get url => _currentUrl;
  bool get isActive => _currentUrl != null;

  void log(String msg) {
    if (kDebugMode) {
      debugPrint(msg);
    }
  }

  bool _isHttpUrl(String u) {
    final uri = Uri.tryParse(u);
    return uri != null && uri.scheme.toLowerCase() == 'http';
  }

  bool _looksLikeImageUrl(String u) {
    final uri = Uri.tryParse(u);
    if (uri == null) return false;
    if (uri.scheme.toLowerCase() != 'https') return false;
    final p = uri.path.toLowerCase();
    return p.endsWith('.png') ||
        p.endsWith('.jpg') ||
        p.endsWith('.jpeg') ||
        p.endsWith('.webp') ||
        p.endsWith('.svg');
  }

  void _attachStatusListener() {
    _statusSub?.cancel();
    _statusSub = _playerService.playerStateStream.listen((s) {
      // IMPORTANT: UI must not infer start phases from PlayerState.
      // The controller is the single authoritative owner of status transitions.
      // This listener only refines playback after source is set (buffering/playing/paused)
      // and handles unexpected player errors.
      if (status == AudioStatus.resolving || status == AudioStatus.loading) {
        return;
      }
      final cur = status;
      AudioStatus next = cur;

      if (s.playing) {
        next = AudioStatus.playing;
      } else if (hasSource) {
        if (s.processingState == ProcessingState.buffering) {
          next = AudioStatus.buffering;
        } else if (cur == AudioStatus.playing || cur == AudioStatus.paused) {
          next = AudioStatus.paused;
        }
      } else {
        // No source:
        // - Do not override buffering (controller may have just set it).
        // - Do not override stopped.
        // - Otherwise, fall back to idle.
        if (cur != AudioStatus.stopped && cur != AudioStatus.buffering) {
          next = AudioStatus.idle;
        }
      }

      if (next != cur) {
        status = next;
        _listenTracker.setHeartbeatEnabled(status == AudioStatus.playing);
        if (status == AudioStatus.buffering) {
          _armBufferingTimeout();
        } else {
          _cancelBufferingTimeout();
        }
        notifyListeners();
      }
    }, onError: (e) {
      status = AudioStatus.error;
      errorMessage = e.toString();
      _listenTracker.setHeartbeatEnabled(false);
      _cancelBufferingTimeout();
      notifyListeners();
    });
  }

  void _cancelBufferingTimeout() {
    try {
      _bufferingTimeout?.cancel();
    } catch (_) {}
    _bufferingTimeout = null;
  }

  void _armBufferingTimeout() {
    _cancelBufferingTimeout();
    final myToken = _opToken;
    _bufferingTimeout = Timer(_bufferingTimeoutDuration, () async {
      if (myToken != _opToken) return;
      if (status != AudioStatus.buffering) return;
      if (_playerService.isPlaying) return;

      _listenTracker.setHeartbeatEnabled(false);
      try {
        await _playerService.stop();
      } catch (_) {}
      _currentUrl = null;
      status = AudioStatus.error;
      errorMessage = 'No internet connection';
      notifyListeners();
    });
  }

  Future<void> playRadioBySlug(String slug) async {
    final myToken = ++_opToken;
    bool isStale() => myToken != _opToken;
    _cancelBufferingTimeout();
    _attachStatusListener();

    await RadioAudioService.ensureInitialized();
    if (isStale()) return;
    final prevSlug = _currentSlug;
    final switching = prevSlug != null && prevSlug != slug;
    if (switching) {
      log('[AudioController] switching station: $prevSlug -> $slug');
      try {
        await _playerService.stop();
      } catch (_) {}
      try {
        await _listenTracker.stop(prevSlug);
      } catch (_) {}
      _currentUrl = null;
      _currentTitle = null;
      _currentSlug = null;
    }

    // Commit user intent immediately so UI can bind the start phases to the
    // correct station tile (spinners/badges should not depend on late success).
    _currentSlug = slug;
    _currentUrl = null;
    status = AudioStatus.resolving;
    errorMessage = null;
    notifyListeners();

    // Resolving: fetch radio detail + build candidate URLs.
    log('[AudioController] fetching radio detail for $slug');
    final res = await ApiClient().get('/live/radio/$slug/');
    if (isStale()) return;
    final m = Map<String, dynamic>.from(res.data as Map);
    final primary =
        (m['stream_url'] ?? m['url_resolved'] ?? m['url'] ?? '').toString();
    final backup = (m['backup_stream_url'] ?? '').toString();
    final name = (m['name'] ?? slug).toString();
    final rawLogo = (m['logo'] ?? '').toString();
    final logoUrl =
        (rawLogo.isEmpty || rawLogo.toLowerCase() == 'null') ? '' : rawLogo;

    _currentTitle = name;
    notifyListeners();

    await RadioAudioService.setNowPlaying(
      id: 'radio:$slug',
      title: name,
      artUri: _looksLikeImageUrl(logoUrl) ? Uri.tryParse(logoUrl) : null,
    );

    final tenant = ApiClient().tenant ?? 'ontime';
    final token = ApiClient().getAccessToken();
    final hasToken = (token ?? '').isNotEmpty;

    final hasHttpStream = _isHttpUrl(primary) || _isHttpUrl(backup);

    final httpsCandidates = resolveRadioStreamUrlsHttpsOnly(
      primary: primary,
      backup: backup,
    );

    // Transition: candidates built.
    status = AudioStatus.loading;
    notifyListeners();

    // Simple policy:
    // - Only allow https:// streams to be passed into ExoPlayer.
    // - If station is http-only, show a clear message and do not attempt playback.
    if (httpsCandidates.isEmpty) {
      status = AudioStatus.error;
      if (hasHttpStream) {
        // If you later re-enable backend proxy, replace this branch with proxy attempt.
        errorMessage = hasToken
            ? l10n.radioHttpProxyUnavailableMultilangMessage()
            : l10n.radioHttpBlockedMultilangMessage();
      } else {
        errorMessage = 'Stream unavailable';
      }
      _currentUrl = null;
      _currentTitle = null;
      _currentSlug = null;
      _listenTracker.setHeartbeatEnabled(false);
      _cancelBufferingTimeout();
      try {
        await _playerService.stop();
      } catch (_) {}
      notifyListeners();
      return;
    }

    final urls = <String>{...httpsCandidates}.toList();
    log('[AudioController] httpsCandidates=${urls.join(' | ')}');

    final start = RadioStartAttempts(_playerService);
    final result = await start.start(
      urls: urls,
      tenant: tenant,
      token: token,
      isStale: isStale,
      onBuffering: () {
        status = AudioStatus.buffering;
        _armBufferingTimeout();
        notifyListeners();
      },
      onPausedBySystem: () {
        status = AudioStatus.paused;
        _pausedBySystem = true;
        _listenTracker.setHeartbeatEnabled(false);
        notifyListeners();
      },
    );
    if (isStale()) return;

    if (result.lastError != null) {
      status = AudioStatus.error;
      if (hasHttpStream && !hasToken) {
        errorMessage = l10n.radioHttpBlockedMultilangMessage();
      } else if (hasHttpStream && hasToken) {
        errorMessage = l10n.radioHttpProxyUnavailableMultilangMessage();
      } else {
        // Preserve the actual playback error for HTTPS streams so the UI/logs show why
        // ExoPlayer started and immediately released.
        errorMessage = result.lastError.toString();
      }
      _currentUrl = null;
      _listenTracker.setHeartbeatEnabled(false);
      try {
        await _playerService.stop();
      } catch (_) {}
      _currentTitle = null;
      _currentSlug = null;
      notifyListeners();
      return;
    }

    status = AudioStatus.playing;
    notifyListeners();

    _currentSlug = slug;
    _currentTitle = name;
    _currentUrl = result.successUrl;

    // Notify UI immediately once playback is started and metadata is committed.
    // Listen tracking should not block the user's loading indicator from dismissing.
    notifyListeners();
    unawaited(() async {
      try {
        await _listenTracker.start(slug);
      } catch (e) {
        log('[AudioController] listenTracker.start failed: ${e.toString()}');
      }
    }());
  }

  Future<void> pause() async {
    await _playerService.pause();
    log('[AudioController] pause()');
    _pausedBySystem = false;
    _cancelBufferingTimeout();
    notifyListeners();
  }

  Future<void> pauseForShorts() async {
    await pause();
  }

  Future<void> play() async {
    await _playerService.play();
    log('[AudioController] resume play()');
    _pausedBySystem = false;
    notifyListeners();
  }

  Future<void> stop() async {
    _opToken++;
    _pausedBySystem = false;
    _cancelBufferingTimeout();
    final slug = _currentSlug;
    _currentUrl = null;
    _currentTitle = null;
    _currentSlug = null;
    status = AudioStatus.stopped;
    errorMessage = null;
    _listenTracker.setHeartbeatEnabled(false);
    notifyListeners();

    try {
      await _playerService.stop();
    } catch (_) {}
    notifyListeners();

    if (slug != null) {
      unawaited(() async {
        try {
          await _listenTracker.stop(slug);
        } catch (e) {
          log('[AudioController] listenTracker.stop failed: ${e.toString()}');
        }
      }());
    }
  }

  @override
  void dispose() {
    try {
      _statusSub?.cancel();
    } catch (_) {}
    try {
      _lifecycleSub?.cancel();
    } catch (_) {}
    _cancelBufferingTimeout();
    _listenTracker.dispose();
    _playerService.dispose();
    super.dispose();
  }
}
