import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../../../auth/tenant_auth_client.dart';
import 'package:url_launcher/url_launcher.dart';

class PlayerPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final int episodeId;
  final int? seasonId; // optional: used for Continue Watching per-season
  final String title;
  final void Function(int episodeId, String? title, String? thumb)? onPlayEpisode; // ask parent to play another ep
  const PlayerPage({
    super.key,
    required this.api,
    required this.tenantId,
    required this.episodeId,
    this.seasonId,
    required this.title,
    this.onPlayEpisode,
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
  bool _ownsController = true; // always owned here for flutter controller
  String _videoId = '';

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
    debugPrint('[PlayerPage] play payload for episode ${widget.episodeId}: $play');
    final raw = (play['video_id'] ?? '').toString();
    final videoId = _extractVideoId(raw);
    debugPrint('[PlayerPage] resolved videoId: "$videoId" from "$raw"');
    _videoId = videoId;
    _token = (play['playback_token'] ?? '').toString();

    if (_token.isNotEmpty) {
      final start = await widget.api.viewStart(
        episodeId: widget.episodeId,
        playbackToken: _token,
      );
      _viewId = (start['view_id'] ?? 0) as int;
    }
    // Create controller for youtube_player_flutter
    final controller = YoutubePlayerController(
      initialVideoId: videoId,
      flags: const YoutubePlayerFlags(
        autoPlay: true,
        mute: false,
        controlsVisibleAtStart: true,
        enableCaption: false,
        forceHD: false,
      ),
    );
    // Listen to state changes
    controller.addListener(() {
      final v = controller.value;
      final st = v.playerState;
      debugPrint('[PlayerPage] state=$st');
      if (st == PlayerState.playing) {
        _startHeartbeat();
        _showEndOverlay = false;
        _pauseTimer?.cancel();
      } else if (st == PlayerState.paused || st == PlayerState.buffering) {
        _stopHeartbeat();
        _pauseTimer?.cancel();
        _pauseTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _showEndOverlay = true);
        });
      } else if (st == PlayerState.ended) {
        _complete();
        _showEndOverlay = true;
      }
      if (mounted) setState(() {});
    });

    setState(() => _yt = controller);
    // Ensure unmuted shortly after init
    Future.delayed(const Duration(milliseconds: 200), () {
      try {
        _yt?.unMute();
      } catch (_) {}
    });

    // If playback doesn’t start shortly, surface a hint for diagnostics
    Future.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      // Heuristic: if overlay is showing or not in playing state yet
      final st = _yt?.value.playerState;
      if (st != PlayerState.playing) {
        debugPrint('[PlayerPage] playback not started after 5s (state=$st). Possible embed restriction or network.');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Video didn\'t start. Check network or embedding permissions.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
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
        _yt?.dispose();
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
        actions: [
          IconButton(
            tooltip: 'Open in YouTube',
            icon: const Icon(Icons.open_in_new),
            onPressed: () async {
              final id = _videoId.trim();
              if (id.isEmpty) return;
              final uri = Uri.parse('https://youtu.be/$id');
              await launchUrl(uri, mode: LaunchMode.externalApplication);
            },
          ),
        ],
      ),
      body: _yt == null
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 900),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: YoutubePlayer(
                        controller: _yt!,
                        showVideoProgressIndicator: true,
                      ),
                    ),
                  ),
                ),
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
