typedef VoidCallbackFn = void Function();

class ChannelNowPlaying {
  final String videoId;
  final String title;
  final String? playlistId;
  final String? playlistTitle;
  final String? thumbnailUrl;
  final bool isPlaying;
  final Duration? playbackPosition;
  final Duration? duration;
  final VoidCallbackFn? onTogglePlayPause;
  final VoidCallbackFn? onExpand;

  const ChannelNowPlaying({
    required this.videoId,
    required this.title,
    required this.isPlaying,
    this.playlistId,
    this.playlistTitle,
    this.thumbnailUrl,
    this.playbackPosition,
    this.duration,
    this.onTogglePlayPause,
    this.onExpand,
  });

  ChannelNowPlaying copyWith({
    String? title,
    String? playlistId,
    String? playlistTitle,
    String? thumbnailUrl,
    bool? isPlaying,
    Duration? playbackPosition,
    Duration? duration,
    VoidCallbackFn? onTogglePlayPause,
    VoidCallbackFn? onExpand,
  }) {
    return ChannelNowPlaying(
      videoId: videoId,
      title: title ?? this.title,
      playlistId: playlistId ?? this.playlistId,
      playlistTitle: playlistTitle ?? this.playlistTitle,
      isPlaying: isPlaying ?? this.isPlaying,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      playbackPosition: playbackPosition ?? this.playbackPosition,
      duration: duration ?? this.duration,
      onTogglePlayPause: onTogglePlayPause ?? this.onTogglePlayPause,
      onExpand: onExpand ?? this.onExpand,
    );
  }
}
