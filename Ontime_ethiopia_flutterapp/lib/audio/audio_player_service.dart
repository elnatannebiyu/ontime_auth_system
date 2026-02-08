import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import 'radio_audio_service.dart';

class AudioPlayerService {
  final AudioPlayer _player = AudioPlayer();
  AudioSession? _session;
  bool _sessionReady = false;
  bool _hasSource = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  StreamSubscription<PlayerState>? _playerStateSub;
  bool _resumeAfterInterruption = false;
  bool _userPaused = false;
  bool _lastPlaying = false;
  final StreamController<bool> _interruptedCtrl =
      StreamController<bool>.broadcast();
  bool _isInterrupted = false;

  Stream<bool> get interruptionStream => _interruptedCtrl.stream;
  bool get isInterrupted => _isInterrupted;

  Future<void> _ensureSession() async {
    if (_sessionReady) return;
    try {
      final session = await AudioSession.instance;
      _session = session;
      await session.configure(const AudioSessionConfiguration.music());

      _interruptionSub = session.interruptionEventStream.listen((event) async {
        if (event.begin) {
          if (kDebugMode) {
            debugPrint(
                '[AudioPlayerService] interruption begin type=${event.type} playing=${_player.playing} lastPlaying=$_lastPlaying userPaused=$_userPaused');
          }
          _isInterrupted = true;
          _interruptedCtrl.add(true);
          _resumeAfterInterruption = _lastPlaying &&
              !_userPaused &&
              event.type == AudioInterruptionType.pause;
          if (kDebugMode) {
            debugPrint(
                '[AudioPlayerService] resumeAfterInterruption=$_resumeAfterInterruption');
          }
          try {
            await pause();
          } catch (_) {}
        } else {
          if (kDebugMode) {
            debugPrint(
                '[AudioPlayerService] interruption end type=${event.type} resumeAfter=$_resumeAfterInterruption hasSource=$_hasSource playing=${_player.playing}');
          }
          _isInterrupted = false;
          _interruptedCtrl.add(false);
          if (_resumeAfterInterruption &&
              _hasSource &&
              event.type == AudioInterruptionType.pause) {
            _resumeAfterInterruption = false;
            if (kDebugMode) {
              debugPrint('[AudioPlayerService] auto-resume play()');
            }
            try {
              await play();
            } catch (_) {}
          }
        }
      });

      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) async {
        try {
          await _player.pause();
        } catch (_) {}
      });

      _playerStateSub = _player.playerStateStream.listen((state) {
        _lastPlaying = state.playing;
      });

      _sessionReady = true;
    } catch (_) {
      _sessionReady = true;
    }
  }

  Future<void> setSource(AudioSource source) async {
    await _ensureSession();
    await _player.setAudioSource(source);
    _hasSource = true;
  }

  Future<void> play() async {
    await _ensureSession();
    try {
      await _session?.setActive(true);
    } catch (_) {}
    await _player.play();
  }

  Future<void> pause() async {
    await _player.pause();
    try {
      await _session?.setActive(false);
    } catch (_) {}
  }

  Future<void> stop() async {
    _userPaused = false;
    if (RadioAudioService.isInitialized) {
      try {
        await RadioAudioService.stopService();
      } catch (_) {
        await _player.stop();
      }
    } else {
      await _player.stop();
    }
    try {
      await _session?.setActive(false);
    } catch (_) {}
    _hasSource = false;
  }

  bool get isPlaying => _player.playing;

  bool get hasSource => _hasSource;

  void setUserPaused(bool value) {
    _userPaused = value;
  }

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  AudioPlayer get player => _player;

  Stream<double> get volumeStream => _player.volumeStream;
  double get volume => _player.volume;
  Future<void> setVolume(double v) => _player.setVolume(v);

  Future<void> dispose() async {
    // Intentionally no-op: the player is owned by AudioPlayerService and is
    // expected to live for the app lifetime.
    try {
      await _interruptionSub?.cancel();
    } catch (_) {}
    try {
      await _becomingNoisySub?.cancel();
    } catch (_) {}
    try {
      await _playerStateSub?.cancel();
    } catch (_) {}
    try {
      await _interruptedCtrl.close();
    } catch (_) {}
  }
}
