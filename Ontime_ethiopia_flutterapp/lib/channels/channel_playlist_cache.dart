class ChannelPlaylistCache {
  ChannelPlaylistCache._();

  static final Map<String, List<Map<String, dynamic>>> playlistsBySlug = {};
  static final Map<String, List<Map<String, dynamic>>> videosByPlaylist = {};
  static final Map<String, Map<String, dynamic>> channelBySlug = {};

  static void clear() {
    playlistsBySlug.clear();
    videosByPlaylist.clear();
    channelBySlug.clear();
  }
}
