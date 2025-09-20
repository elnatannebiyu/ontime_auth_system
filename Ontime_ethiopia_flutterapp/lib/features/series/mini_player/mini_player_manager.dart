import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../auth/tenant_auth_client.dart';
import '../pages/player_page.dart';

class MiniPlayerManager {
  MiniPlayerManager._();
  static final MiniPlayerManager instance = MiniPlayerManager._();

  late AuthApi _api;
  late String _tenantId;
  GlobalKey<NavigatorState>? _navKey;

  YoutubePlayerController? _controller;
  OverlayEntry? _entry;
  bool get isActive => _entry != null;

  // Meta
  String? _title;
  int? _episodeId;
  int? _seasonId;

  void attach(
      {required GlobalKey<NavigatorState> navKey,
      required AuthApi api,
      required String tenantId}) {
    _navKey = navKey;
    _api = api;
    _tenantId = tenantId;
  }

  Future<void> play({
    required int episodeId,
    required int? seasonId,
    required String title,
    String? thumb,
  }) async {
    _title = title;
    _episodeId = episodeId;
    _seasonId = seasonId;

    _api.setTenant(_tenantId);
    final play = await _api.seriesEpisodePlay(episodeId);
    final raw = (play['video_id'] ?? '').toString();
    final videoId = _extractVideoId(raw);

    // Reuse existing controller when possible to avoid WKWebView teardown issues
    _controller ??= YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        playsInline: true,
        strictRelatedVideos: true,
        enableCaption: false,
        mute: true,
      ),
    );
    _controller!.loadVideoById(videoId: videoId, startSeconds: 0);
    // Kick playback explicitly (helps on some platforms)
    scheduleMicrotask(() {
      try {
        _controller?.playVideo();
      } catch (_) {}
    });
    Future.delayed(const Duration(milliseconds: 200), () {
      try {
        _controller?.playVideo();
      } catch (_) {}
    });

    // Listen for "cued" state and try to start (common with autoplay restrictions)
    _controller!.listen((value) {
      final st = value.playerState;
      if (st == PlayerState.cued) {
        try {
          _controller?.playVideo();
        } catch (_) {}
      }
    });

    _ensureOverlay();
    _markNeedsBuild();
    // Also try after the first overlay frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        _controller?.playVideo();
      } catch (_) {}
    });
  }

  void pause() => _controller?.pauseVideo();
  void resume() => _controller?.playVideo();

  void close() {
    try {
      if (!Platform.isIOS) {
        _controller?.close().catchError((_) {});
      }
    } catch (_) {}
    _controller = null;
    _entry?.remove();
    _entry = null;
  }

  void _hideOverlay() {
    _entry?.remove();
    _entry = null;
  }

  void showOverlay() {
    _ensureOverlay();
    _markNeedsBuild();
  }

  // Take over an existing controller and metadata (used when minimizing from full player)
  void adoptController({
    required YoutubePlayerController controller,
    required int episodeId,
    required String title,
    int? seasonId,
  }) {
    if (_controller != null && !identical(_controller, controller)) {
      try {
        if (!Platform.isIOS) {
          _controller!.close().catchError((_) {});
        }
      } catch (_) {}
    }
    _controller = controller;
    _episodeId = episodeId;
    _seasonId = seasonId;
    _title = title;
  }

  void _ensureOverlay() {
    if (_entry != null) return;
    final overlay = _navKey?.currentState?.overlay;
    if (overlay == null) return;
    _entry = OverlayEntry(builder: (ctx) => _MiniPlayerBar(manager: this));
    overlay.insert(_entry!);
  }

  void _markNeedsBuild() => _entry?.markNeedsBuild();

  // Extract a single YouTube video ID from various URL formats; ignore playlist/list params
  String _extractVideoId(String input) {
    String s = input.trim();
    if (s.isEmpty) return '';
    // If it's already a likely video ID (11 chars, allowed charset)
    final idLike = RegExp(r'^[A-Za-z0-9_-]{11}$');
    if (idLike.hasMatch(s)) return s;
    // Short URL youtu.be/VIDEOID
    final short = RegExp(r'youtu\.be/([A-Za-z0-9_-]{11})');
    final m1 = short.firstMatch(s);
    if (m1 != null) return m1.group(1)!;
    // watch?v=VIDEOID
    final watch = RegExp(r'[?&]v=([A-Za-z0-9_-]{11})');
    final m2 = watch.firstMatch(s);
    if (m2 != null) return m2.group(1)!;
    // embed/VIDEOID
    final embed = RegExp(r'embed/([A-Za-z0-9_-]{11})');
    final m3 = embed.firstMatch(s);
    if (m3 != null) return m3.group(1)!;
    // Fallback: strip known list param if present and try again
    final noList = s.replaceAll(RegExp(r'[?&]list=[^&]+'), '');
    final m4 = watch.firstMatch(noList);
    if (m4 != null) return m4.group(1)!;
    return s; // last resort
  }
}

class _MiniPlayerBar extends StatefulWidget {
  final MiniPlayerManager manager;
  const _MiniPlayerBar({required this.manager});

  @override
  State<_MiniPlayerBar> createState() => _MiniPlayerBarState();
}

class _MiniPlayerBarState extends State<_MiniPlayerBar> {
  @override
  Widget build(BuildContext context) {
    final m = widget.manager;
    final c = m._controller;
    if (c == null) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: 12,
          right: 12,
          bottom: 12 + MediaQuery.of(context).padding.bottom,
        ),
        child: Material(
          elevation: 8,
          borderRadius: BorderRadius.circular(12),
          color: Theme.of(context).colorScheme.surface,
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              final m = widget.manager;
              final epId = m._episodeId;
              if (epId == null) return;
              // Hide only the overlay, keep controller alive to continue playback
              m._hideOverlay();
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => PlayerPage(
                    api: m._api,
                    tenantId: m._tenantId,
                    episodeId: epId,
                    seasonId: m._seasonId,
                    title: m._title ?? 'Now Playing',
                    controller: c,
                    onPlayEpisode: (nextId, nextTitle, nextThumb) {
                      MiniPlayerManager.instance.play(
                        episodeId: nextId,
                        seasonId: m._seasonId,
                        title: nextTitle ?? m._title ?? 'Now Playing',
                        thumb: nextThumb,
                      );
                    },
                  ),
                ),
              );
            },
            child: Container(
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: SizedBox(
                      width: 92,
                      height: 48,
                      child: YoutubePlayer(controller: c),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        m._title ?? 'Now Playing',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(fontSize: 12),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => m.close(),
                  )
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
