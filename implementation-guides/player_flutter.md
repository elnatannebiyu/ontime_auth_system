# Player & View Tracking — Flutter Implementation Guide

This document shows how to integrate a YouTube player in Flutter so that:
- YouTube receives a real view (official IFrame player)
- Your backend receives view analytics (start/heartbeat/complete)

Targets `Ontime_ethiopia_flutterapp/`.

---

## Overview
- Use `youtube_player_iframe` to embed the official YouTube IFrame player.
- Call backend `/api/series/episodes/{id}/play/` to get `{ video_id, provider }`.
- On first play, POST `/api/series/views/start` to create a view record.
- Send `/api/series/views/heartbeat` every ~15s while playing.
- On end/back, POST `/api/series/views/complete`.

## Dependencies
Add to `pubspec.yaml`:
```yaml
dependencies:
  youtube_player_iframe: ^5.1.2
```

## API Surface (AuthApi)
Add minimal methods:
```dart
Future<Map<String, dynamic>> seriesEpisodePlay(int episodeId);
Future<Map<String, dynamic>> viewStart({required int episodeId, required String playbackToken});
Future<void> viewHeartbeat({required int viewId, required String playbackToken, required int secondsWatched, String state = 'playing', int? positionSeconds});
Future<void> viewComplete({required int viewId, required String playbackToken, required int totalSeconds});
```

These call respectively:
- `GET /api/series/episodes/{id}/play/`
- `POST /api/series/views/start`
- `POST /api/series/views/heartbeat`
- `POST /api/series/views/complete`

All requests must include `X-Tenant-Id` and Authorization headers (already handled by `AuthApi`).

## Player Page Skeleton
Create `lib/features/series/pages/player_page.dart`:
```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';
import '../../../auth/tenant_auth_client.dart';

class PlayerPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final int episodeId;
  final String title;
  const PlayerPage({super.key, required this.api, required this.tenantId, required this.episodeId, required this.title});

  @override
  State<PlayerPage> createState() => _PlayerPageState();
}

class _PlayerPageState extends State<PlayerPage> {
  YoutubePlayerController? _yt;
  Timer? _hb;
  int _viewId = 0;
  String _token = '';
  int _accum = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    widget.api.setTenant(widget.tenantId);
    final play = await widget.api.seriesEpisodePlay(widget.episodeId); // { video_id, provider, playback_token? }
    final videoId = (play['video_id'] ?? '').toString();
    _token = (play['playback_token'] ?? '') as String? ?? '';

    // Start view
    if (_token.isNotEmpty) {
      final start = await widget.api.viewStart(episodeId: widget.episodeId, playbackToken: _token);
      _viewId = (start['view_id'] ?? 0) as int;
    }

    _yt = YoutubePlayerController(
      params: const YoutubePlayerParams(
        showControls: true,
        mute: false,
        playsInline: true,
      ),
    );
    _yt!.loadVideoById(videoId: videoId);

    _yt!.listen((value) {
      final state = value.playerState;
      if (state == PlayerState.playing) {
        _startHeartbeat();
      } else {
        _stopHeartbeat();
      }
      if (state == PlayerState.ended) {
        _complete();
      }
    });
  }

  void _startHeartbeat() {
    _hb ??= Timer.periodic(const Duration(seconds: 15), (_) async {
      _accum += 15;
      if (_viewId > 0 && _token.isNotEmpty) {
        await widget.api.viewHeartbeat(viewId: _viewId, playbackToken: _token, secondsWatched: 15, state: 'playing');
      }
    });
  }

  void _stopHeartbeat() {
    _hb?.cancel();
    _hb = null;
  }

  Future<void> _complete() async {
    _stopHeartbeat();
    if (_viewId > 0 && _token.isNotEmpty) {
      await widget.api.viewComplete(viewId: _viewId, playbackToken: _token, totalSeconds: _accum);
    }
  }

  @override
  void dispose() {
    _complete();
    _yt?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _yt == null
          ? const Center(child: CircularProgressIndicator())
          : YoutubePlayer(controller: _yt!),
    );
  }
}
```

## Wiring from Episodes Page
In your episodes list, replace the SnackBar with navigation to `PlayerPage`, passing `episodeId` and `title`.

## UX Notes
- Do not autoplay with sound off in ways that break YouTube policies. Let user tap to play.
- Pause heartbeat when app is backgrounded (AppLifecycleState) or page is not visible.
- If network drops, buffer heartbeats and send on reconnect (optional).

## Validation Checklist
- Absolute `cover_image` URLs load on Shows/Seasons pages.
- Tapping an episode opens the YouTube player.
- Backend receives view `start` then periodic `heartbeat` then `complete`.
- Your Episode ordering is by manual `episode_number`.

## Future Enhancements
- Show picture-in-picture mini player.
- Support HLS/MP4 with `video_player` for non-YouTube sources using the same analytics.
- Show watch progress per episode using heartbeats.
