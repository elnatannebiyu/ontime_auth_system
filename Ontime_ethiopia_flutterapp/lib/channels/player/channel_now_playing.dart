typedef VoidCallbackFn = void Function();

class ChannelNowPlaying {
  final String videoId;
  final String title;
  final String? playlistId;
  final String? playlistTitle;
  final String? thumbnailUrl;
  final bool isPlaying;
  final VoidCallbackFn? onTogglePlayPause;
  final VoidCallbackFn? onExpand;

  const ChannelNowPlaying({
    required this.videoId,
    required this.title,
    required this.isPlaying,
    this.playlistId,
    this.playlistTitle,
    this.thumbnailUrl,
    this.onTogglePlayPause,
    this.onExpand,
  });

  ChannelNowPlaying copyWith({
    String? title,
    String? playlistId,
    String? playlistTitle,
    String? thumbnailUrl,
    bool? isPlaying,
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
      onTogglePlayPause: onTogglePlayPause ?? this.onTogglePlayPause,
      onExpand: onExpand ?? this.onExpand,
    );
  }
}
