// Model for now playing state

typedef VoidCallbackFn = void Function();

class SeriesNowPlaying {
  final int episodeId;
  final String title;
  final String? thumbnailUrl;
  final Duration position;
  final Duration duration;
  final bool isPlaying;

  // Optional control callbacks (provided by PlayerPage when active)
  final VoidCallbackFn? onTogglePlayPause;
  final VoidCallbackFn? onExpand;

  const SeriesNowPlaying({
    required this.episodeId,
    required this.title,
    required this.position,
    required this.duration,
    required this.isPlaying,
    this.thumbnailUrl,
    this.onTogglePlayPause,
    this.onExpand,
  });

  SeriesNowPlaying copyWith({
    String? title,
    String? thumbnailUrl,
    Duration? position,
    Duration? duration,
    bool? isPlaying,
    VoidCallbackFn? onTogglePlayPause,
    VoidCallbackFn? onExpand,
  }) {
    return SeriesNowPlaying(
      episodeId: episodeId,
      title: title ?? this.title,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isPlaying: isPlaying ?? this.isPlaying,
      onTogglePlayPause: onTogglePlayPause ?? this.onTogglePlayPause,
      onExpand: onExpand ?? this.onExpand,
    );
  }
}


