// ignore_for_file: unused_field

import 'dart:async';
import 'package:flutter/material.dart';
import '../../../auth/tenant_auth_client.dart';
import '../pages/player_page.dart';

class MiniPlayerManager {
  MiniPlayerManager._();
  static final MiniPlayerManager instance = MiniPlayerManager._();

  late AuthApi _api;
  late String _tenantId;
  GlobalKey<NavigatorState>? _navKey;

  bool get isActive => false;

  // Meta (for future use)
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

  Future<void> play(
      {required int episodeId,
      required int? seasonId,
      required String title,
      String? thumb}) async {
    _title = title;
    _episodeId = episodeId;
    _seasonId = seasonId;
    final ctx = _navKey?.currentContext;
    if (ctx == null) return;
    await Navigator.of(ctx).push(MaterialPageRoute(
      builder: (_) => PlayerPage(
        api: _api,
        tenantId: _tenantId,
        episodeId: episodeId,
        seasonId: seasonId,
        title: title,
        onPlayEpisode: (nextId, nextTitle, nextThumb) {
          // Chain to next episode in full-page mode
          MiniPlayerManager.instance.play(
            episodeId: nextId,
            seasonId: seasonId,
            title: nextTitle ?? title,
            thumb: nextThumb,
          );
        },
      ),
    ));
  }

  void pause() {}
  void resume() {}
  void close() {}
  void showOverlay() {}
}
