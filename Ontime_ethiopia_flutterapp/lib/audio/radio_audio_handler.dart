import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class RadioAudioHandler extends BaseAudioHandler {
  RadioAudioHandler(this._player) {
    _attach();
  }

  final AudioPlayer _player;
  StreamSubscription<PlaybackEvent>? _eventSub;
  bool _explicitlyStopped = true;

  void _attach() {
    _eventSub?.cancel();
    _eventSub = _player.playbackEventStream.listen((event) {
      if (_explicitlyStopped) return;
      playbackState.add(_transformEvent(event));
    });
  }

  void setNowPlaying(MediaItem item) {
    _explicitlyStopped = false;
    mediaItem.add(item);
  }

  PlaybackState _transformEvent(PlaybackEvent event) {
    final playing = _player.playing;
    final processingState = _player.processingState;

    AudioProcessingState aps;
    switch (processingState) {
      case ProcessingState.idle:
        aps = AudioProcessingState.idle;
        break;
      case ProcessingState.loading:
        aps = AudioProcessingState.loading;
        break;
      case ProcessingState.buffering:
        aps = AudioProcessingState.buffering;
        break;
      case ProcessingState.ready:
        aps = AudioProcessingState.ready;
        break;
      case ProcessingState.completed:
        aps = AudioProcessingState.completed;
        break;
    }

    final controls = _explicitlyStopped
        ? <MediaControl>[]
        : (playing
            ? <MediaControl>[MediaControl.pause, MediaControl.stop]
            : <MediaControl>[MediaControl.play, MediaControl.stop]);
    final compactActionIndices = controls.length == 2
        ? const [0, 1]
        : (controls.isEmpty ? const <int>[] : const [0]);

    return PlaybackState(
      controls: controls,
      systemActions: _explicitlyStopped
          ? const {}
          : const {
              MediaAction.play,
              MediaAction.pause,
              MediaAction.stop,
            },
      androidCompactActionIndices: compactActionIndices,
      processingState: aps,
      playing: playing,
      updatePosition: _player.position,
      bufferedPosition: _player.bufferedPosition,
      speed: _player.speed,
    );
  }

  @override
  Future<void> play() {
    _explicitlyStopped = false;
    if (_eventSub == null) {
      _attach();
    }
    playbackState.add(_transformEvent(_player.playbackEvent));
    return _player.play();
  }

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> stop() async {
    _explicitlyStopped = true;
    try {
      await _eventSub?.cancel();
    } catch (_) {}
    _eventSub = null;
    await _player.stop();
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(
        controls: [],
        systemActions: {},
        androidCompactActionIndices: [],
        processingState: AudioProcessingState.idle,
        playing: false,
      ),
    );
    await super.stop();
  }

  Future<void> dispose() async {
    await _eventSub?.cancel();
  }
}
