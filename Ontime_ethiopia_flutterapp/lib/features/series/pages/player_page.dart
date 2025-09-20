import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../auth/tenant_auth_client.dart';

class PlayerPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final int episodeId;
  final int? seasonId; // optional: used for Continue Watching per-season
  final String title;
  final void Function(int episodeId, String? title, String? thumb)? onPlayEpisode; // ask parent to play another ep
  final YoutubePlayerController? controller; // reuse existing controller (e.g., from mini player)
  const PlayerPage({
    super.key,
    required this.api,
    required this.tenantId,
    required this.episodeId,
    this.seasonId,
    required this.title,
    this.onPlayEpisode,
    this.controller,
  });

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  YoutubePlayerController? _yt;
  Timer? _hb;
  int _viewId = 0;
  String _token = '';
  int _accum = 0;
  bool _showEndOverlay = false;
  Timer? _pauseTimer;
  List<Map<String, dynamic>> _seasonEpisodes = const [];
  bool _ownsController = false; // only close if we created it here

  @override
  void initState() {
    super.initState();
    _init();
  }

  // Extract a single YouTube video ID from various URL formats; ignore playlist/list params.
  String _extractVideoId(String input) {
    String s = input.trim();
    if (s.isEmpty) return '';
    final idLike = RegExp(r'^[A-Za-z0-9_-]{11}$');
    if (idLike.hasMatch(s)) return s;
    final short = RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})');
    final m1 = short.firstMatch(s);
    if (m1 != null) return m1.group(1)!;
    final watch = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');
    final m2 = watch.firstMatch(s);
    if (m2 != null) return m2.group(1)!;
    final embed = RegExp(r'embed/([A-Za-z0-9_-]{11})');
    final m3 = embed.firstMatch(s);
    if (m3 != null) return m3.group(1)!;
    final noList = s.replaceAll(RegExp(r'[?&]list=[^&]+'), '');
    final m4 = watch.firstMatch(noList);
    if (m4 != null) return m4.group(1)!;
    return s;
  }

  String _pickThumb(Map<String, dynamic>? thumbs) {
    if (thumbs == null) return '';
    const order = ['maxres', 'standard', 'high', 'medium', 'default'];
    for (final k in order) {
      final t = thumbs[k];
      if (t is Map && t['url'] is String && (t['url'] as String).isNotEmpty) {
        return t['url'] as String;
      }
    }
    if (thumbs['url'] is String) return thumbs['url'] as String;
    return '';
  }

  Future<void> _init() async {
    widget.api.setTenant(widget.tenantId);
    final play = await widget.api.seriesEpisodePlay(widget.episodeId);
    final raw = (play['video_id'] ?? '').toString();
    final videoId = _extractVideoId(raw);
    _token = (play['playback_token'] ?? '').toString();

    if (_token.isNotEmpty) {
      final start = await widget.api.viewStart(
        episodeId: widget.episodeId,
        playbackToken: _token,
      );
      _viewId = (start['view_id'] ?? 0) as int;
    }

    YoutubePlayerController controller;
    if (widget.controller != null) {
      controller = widget.controller!;
      _ownsController = false;
    } else {
      controller = YoutubePlayerController(
        params: const YoutubePlayerParams(
          // UI controls
          showControls: true,
          showFullscreenButton: true,
          playsInline: true,
          // Minimize suggestions
          strictRelatedVideos: true, // rel=0 → show related from same channel
          enableCaption: false,
        ),
      );
      controller.loadVideoById(videoId: videoId, startSeconds: 0);
      _ownsController = true;
    }

    controller.listen((value) {
      final state = value.playerState;
      if (state == PlayerState.playing) {
        _startHeartbeat();
        _showEndOverlay = false;
        _pauseTimer?.cancel();
      } else if (state == PlayerState.paused || state == PlayerState.buffering) {
        _stopHeartbeat();
        // If paused for more than 2 seconds, show overlay to block suggestions grid
        _pauseTimer?.cancel();
        _pauseTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showEndOverlay = true);
        });
      } else if (state == PlayerState.ended) {
        _complete();
        _showEndOverlay = true;
      }
      if (mounted) setState(() {});
    });

    setState(() {
      _yt = controller;
    });


    // Preload season episodes for suggestions overlay
    if (widget.seasonId != null) {
      try {
        final results = await widget.api.seriesEpisodesForSeason(widget.seasonId!);
        if (mounted) setState(() => _seasonEpisodes = results);
      } catch (_) {}
    }
  }

  void _startHeartbeat() {
    _hb ??= Timer.periodic(const Duration(seconds: 15), (_) async {
      _accum += 15;
      if (_viewId > 0 && _token.isNotEmpty) {
        try {
          await widget.api.viewHeartbeat(
            viewId: _viewId,
            playbackToken: _token,
            secondsWatched: 15,
            state: 'playing',
          );
        } catch (_) {}
      }
      // Save Continue Watching marker locally (dev-friendly, fast)
      _saveContinueWatching();
    });
  }

  void _stopHeartbeat() {
    _hb?.cancel();
    _hb = null;
  }

  Future<void> _complete() async {
    _stopHeartbeat();
    if (_viewId > 0 && _token.isNotEmpty) {
      try {
        await widget.api.viewComplete(
          viewId: _viewId,
          playbackToken: _token,
          totalSeconds: _accum,
        );
      } catch (_) {}
    }
    await _saveContinueWatching();
  }

  Future<void> _saveContinueWatching() async {
    final sid = widget.seasonId;
    if (sid == null) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'cw_season_$sid';
      // Minimal payload
      final payload = {
        'episode_id': widget.episodeId,
        'title': widget.title,
        'season_id': sid,
        'updated_at': DateTime.now().toIso8601String(),
      };
      // Store as JSON string
      final jsonStr = jsonEncode(payload);
      await prefs.setString(key, jsonStr);
    } catch (_) {}
  }

  @override
  void dispose() {
    _complete();
    if (_ownsController) {
      try {
        _yt?.close();
      } catch (_) {}
    }
    _pauseTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: const [],
      ),
      body: _yt == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Positioned.fill(child: YoutubePlayer(controller: _yt!)),
                // Top area is fully clickable now (removed tap blockers)
                // Central overlay to block end-screen suggestion grid (keeps bottom controls clickable)
                if (_showEndOverlay)
                  Positioned(
                    top: 40,
                    left: 0,
                    right: 0,
                    bottom: 60,
                    child: AbsorbPointer(
                      absorbing: true,
                      child: Container(color: Colors.transparent),
                    ),
                  ),
                // Our own suggestions overlay (device-agnostic), shown when paused long or ended
                if (_showEndOverlay)
                  Positioned(
                    right: 12,
                    bottom: 76,
                    child: _buildOurSuggestions(),
                  ),
              ],
            ),
    );
  }

  Widget _buildOurSuggestions() {
    if (_seasonEpisodes.isEmpty || widget.onPlayEpisode == null || widget.seasonId == null) {
      return const SizedBox.shrink();
    }
    final idx = _seasonEpisodes.indexWhere((e) => e['id'] == widget.episodeId);
    final next = <Map<String, dynamic>>[];
    if (idx >= 0) {
      if (idx + 1 < _seasonEpisodes.length) next.add(_seasonEpisodes[idx + 1]);
      if (idx + 2 < _seasonEpisodes.length) next.add(_seasonEpisodes[idx + 2]);
    } else {
      next.addAll(_seasonEpisodes.take(2));
    }
    if (next.isEmpty) return const SizedBox.shrink();

    return Material(
      color: Colors.black.withOpacity(0.6),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: next.map((e) {
            final id = e['id'] as int;
            final title = (e['display_title'] ?? e['title'] ?? '').toString();
            final thumbs = e['thumbnails'] as Map<String, dynamic>?;
            final thumb = _pickThumb(thumbs);
            return GestureDetector(
              onTap: () {
                Navigator.of(context).maybePop();
                final cb = widget.onPlayEpisode;
                if (cb != null) {
                  WidgetsBinding.instance.addPostFrameCallback((_) => cb(id, title, thumb));
                }
              },
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 6),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.network(
                        thumb,
                        width: 150,
                        height: 84,
                        fit: BoxFit.cover,
                      ),
                    ),
                    const SizedBox(height: 6),
                    SizedBox(
                      width: 150,
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
