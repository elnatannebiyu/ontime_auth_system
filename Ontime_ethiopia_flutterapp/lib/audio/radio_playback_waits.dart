import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:just_audio/just_audio.dart';

import 'app_lifecycle_signal.dart';
import 'audio_player_service.dart';

class RadioPlaybackWaits {
  final AudioPlayerService playerService;

  RadioPlaybackWaits(this.playerService);

  Future<void> waitReadyOrBuffering(Duration budget) async {
    await playerService.playerStateStream
        .firstWhere((s) =>
            s.processingState == ProcessingState.ready ||
            s.processingState == ProcessingState.buffering)
        .timeout(budget);
  }

  Future<void> waitPlayingWithInterruption({
    required Duration waitBudget,
    required bool Function() isStale,
    required void Function() onPausedBySystem,
  }) async {
    try {
      final alreadyInterrupted = playerService.isInterrupted;

      final playingFuture = playerService.playerStateStream
          .firstWhere((s) => s.playing)
          .then((_) => true);
      final interruptedFuture = playerService.interruptionStream
          .firstWhere((v) => v == true)
          .then((_) => false);
      final inactiveFuture = AppLifecycleSignal.I.stream
          .firstWhere((s) => s == AppLifecycleState.inactive)
          .then((_) => false);

      final playingWon = alreadyInterrupted
          ? false
          : await Future.any([playingFuture, interruptedFuture, inactiveFuture])
              .timeout(waitBudget);

      if (!playingWon) {
        onPausedBySystem();

        await Future.any([
          playerService.interruptionStream.firstWhere((v) => v == false),
          AppLifecycleSignal.I.stream
              .firstWhere((s) => s == AppLifecycleState.resumed)
              .then((_) => null),
        ]).timeout(const Duration(minutes: 2));
        if (isStale()) return;

        await playerService.play();
        await playerService.playerStateStream
            .firstWhere((s) => s.playing)
            .timeout(waitBudget);
      }
    } on TimeoutException {
      bool wasInterrupted = playerService.isInterrupted;
      if (!wasInterrupted) {
        try {
          await playerService.interruptionStream
              .firstWhere((v) => v == true)
              .timeout(const Duration(milliseconds: 350));
          wasInterrupted = true;
        } catch (_) {
          wasInterrupted = false;
        }
      }

      if (!wasInterrupted) {
        try {
          await AppLifecycleSignal.I.stream
              .firstWhere((s) => s == AppLifecycleState.inactive)
              .timeout(const Duration(milliseconds: 350));
          wasInterrupted = true;
        } catch (_) {}
      }

      if (wasInterrupted) {
        onPausedBySystem();

        await Future.any([
          playerService.interruptionStream.firstWhere((v) => v == false),
          AppLifecycleSignal.I.stream
              .firstWhere((s) => s == AppLifecycleState.resumed)
              .then((_) => null),
        ]).timeout(const Duration(minutes: 2));
        if (isStale()) return;

        await playerService.play();
        await playerService.playerStateStream
            .firstWhere((s) => s.playing)
            .timeout(waitBudget);
        return;
      }

      rethrow;
    }
  }
}
