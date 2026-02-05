import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:just_audio/just_audio.dart';

import 'radio_audio_service.dart';

class AudioPlayerService {
  final AudioPlayer _player = RadioAudioService.player;
  AudioSession? _session;
  bool _sessionReady = false;
  bool _hasSource = false;
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;
  bool _resumeAfterInterruption = false;
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
          _isInterrupted = true;
          _interruptedCtrl.add(true);
          _resumeAfterInterruption = _player.playing || _hasSource;
          try {
            await pause();
          } catch (_) {}
        } else {
          _isInterrupted = false;
          _interruptedCtrl.add(false);
          if (_resumeAfterInterruption && _hasSource) {
            _resumeAfterInterruption = false;
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

  Stream<PlayerState> get playerStateStream => _player.playerStateStream;

  Stream<double> get volumeStream => _player.volumeStream;
  double get volume => _player.volume;
  Future<void> setVolume(double v) => _player.setVolume(v);

  Future<void> dispose() async {
    // Intentionally no-op: the underlying player is owned by RadioAudioService.
    try {
      await _interruptionSub?.cancel();
    } catch (_) {}
    try {
      await _becomingNoisySub?.cancel();
    } catch (_) {}
    try {
      await _interruptedCtrl.close();
    } catch (_) {}
  }
}
