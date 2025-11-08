import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'audio_controller.dart';
import 'tv_controller.dart';

class RadioPlayerPage extends StatefulWidget {
  final String slug;
  const RadioPlayerPage({super.key, required this.slug});

  @override
  State<RadioPlayerPage> createState() => _RadioPlayerPageState();
}

class _RadioPlayerPageState extends State<RadioPlayerPage> {
  final _audio = AudioController.instance;
  late final Stream<PlayerState> _stateStream;
  bool _booting = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _stateStream = _audio.player.playerStateStream;
    _start();
  }

  Future<void> _start() async {
    setState(() {
      _booting = true;
      _error = null;
    });
    try {
      // Replacement policy: opening Radio stops TV
      try {
        await TvController.instance.stop();
      } catch (_) {}

      // If already on this station and ready/buffering/playing, don't reload
      final ps = _audio.player.playerState;
      final isActive = _audio.slug == widget.slug &&
          (ps.playing ||
              ps.processingState == ProcessingState.ready ||
              ps.processingState == ProcessingState.buffering);
      if (!isActive) {
        await _audio
            .playRadioBySlug(widget.slug)
            .timeout(const Duration(seconds: 20));
      }
    } catch (e) {
      _error = 'Failed to start radio';
    } finally {
      if (mounted)
        setState(() {
          _booting = false;
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        // Keep radio alive for mini bar; do not stop here.
        return true;
      },
      child: Scaffold(
        appBar: AppBar(title: Text(_audio.title ?? 'Radio')),
        body: _error != null
            ? Center(child: Text(_error!))
            : _booting
                ? const Center(child: CircularProgressIndicator())
                : Column(
                    children: [
                      const SizedBox(height: 16),
                      if ((_audio.url ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: Text(_audio.url!,
                              style: const TextStyle(fontSize: 12),
                              textAlign: TextAlign.center),
                        ),
                      const SizedBox(height: 16),
                      StreamBuilder<PlayerState>(
                        stream: _stateStream,
                        initialData: _audio.player.playerState,
                        builder: (context, snap) {
                          final st = snap.data ?? _audio.player.playerState;
                          final playing = st.playing;
                          final buffering = st.processingState ==
                                  ProcessingState.loading ||
                              st.processingState == ProcessingState.buffering;
                          return Column(
                            children: [
                              if (buffering) const LinearProgressIndicator(),
                              const SizedBox(height: 12),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    iconSize: 64,
                                    icon: Icon(playing
                                        ? Icons.pause_circle
                                        : Icons.play_circle),
                                    onPressed: () async {
                                      try {
                                        if (playing) {
                                          await _audio.pause();
                                        } else {
                                          await _audio.play();
                                        }
                                      } catch (_) {}
                                    },
                                  ),
                                  const SizedBox(width: 12),
                                  IconButton(
                                    tooltip: 'Stop',
                                    icon:
                                        const Icon(Icons.stop_circle, size: 40),
                                    onPressed: () async {
                                      try {
                                        await _audio.stop();
                                      } catch (_) {}
                                    },
                                  ),
                                ],
                              ),
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 12),
                      StreamBuilder<double>(
                        stream: _audio.player.volumeStream,
                        initialData: _audio.player.volume,
                        builder: (context, snap) {
                          final v = snap.data ?? 1.0;
                          return Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                const Icon(Icons.volume_down),
                                Expanded(
                                    child: Slider(
                                        value: v,
                                        onChanged: (x) =>
                                            _audio.player.setVolume(x),
                                        min: 0,
                                        max: 1.0)),
                                const Icon(Icons.volume_up),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
      ),
    );
  }
}
