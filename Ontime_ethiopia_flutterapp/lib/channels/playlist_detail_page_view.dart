import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import 'channel_ui_utils.dart';
import 'player/channel_mini_player_manager.dart';
import 'player/channel_now_playing.dart';

class PlaylistDetailPageView extends StatelessWidget {
  final String appBarTitle;
  final bool isLandscape;
  final bool minimized;
  final Future<bool> Function() onWillPop;

  final Widget? headerPlayer;
  final Map<String, dynamic>? headerVideo;

  final Set<String> watchedVideoIds;
  final VoidCallback onToggleNowPlayingExpanded;
  final bool nowPlayingExpanded;

  final bool remindAvailable;
  final bool loadingReminder;
  final bool remindOn;
  final VoidCallback onToggleReminder;

  final List<Widget> listHeader;
  final int headerCount;
  final double listBottomPad;

  final List<Map<String, dynamic>> videos;
  final bool loadingMore;
  final bool hasNext;
  final ScrollController scrollController;

  final Future<void> Function() onRefresh;
  final void Function(Map<String, dynamic> video) onTapVideo;
  final void Function(String videoId) onToggleWatched;

  const PlaylistDetailPageView({
    super.key,
    required this.appBarTitle,
    required this.isLandscape,
    required this.minimized,
    required this.onWillPop,
    required this.headerPlayer,
    required this.headerVideo,
    required this.watchedVideoIds,
    required this.onToggleNowPlayingExpanded,
    required this.nowPlayingExpanded,
    required this.remindAvailable,
    required this.loadingReminder,
    required this.remindOn,
    required this.onToggleReminder,
    required this.listHeader,
    required this.headerCount,
    required this.listBottomPad,
    required this.videos,
    required this.loadingMore,
    required this.hasNext,
    required this.scrollController,
    required this.onRefresh,
    required this.onTapVideo,
    required this.onToggleWatched,
  });

  @override
  Widget build(BuildContext context) {
    if (isLandscape && !minimized && headerVideo != null) {
      return WillPopScope(
        onWillPop: onWillPop,
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: null,
          body: SafeArea(
            top: false,
            bottom: false,
            child: Center(
              child: headerPlayer ?? const SizedBox.shrink(),
            ),
          ),
        ),
      );
    }

    return WillPopScope(
      onWillPop: onWillPop,
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        appBar: isLandscape ? null : AppBar(title: Text(appBarTitle)),
        body: SafeArea(
          top: false,
          bottom: false,
          left: isLandscape,
          right: isLandscape,
          child: Column(
            children: [
              if (headerPlayer != null)
                Flexible(
                  fit: FlexFit.loose,
                  child: headerPlayer!,
                ),
              if (!minimized && headerPlayer != null)
                const Divider(
                  height: 1,
                  thickness: 1,
                  color: Colors.white,
                ),
              if (!minimized && headerVideo != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            final id =
                                (headerVideo!['id'] ?? '').toString().trim();
                            onToggleWatched(id);
                          },
                          icon: Icon(
                            watchedVideoIds.contains(
                                    (headerVideo!['id'] ?? '').toString())
                                ? Icons.check_circle
                                : Icons.check_circle_outline,
                          ),
                          label: Text(
                            watchedVideoIds.contains(
                                    (headerVideo!['id'] ?? '').toString())
                                ? 'Watched'
                                : 'Mark as watched',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: (!remindAvailable || loadingReminder)
                              ? null
                              : onToggleReminder,
                          icon: Icon(
                            remindOn
                                ? Icons.notifications_active
                                : Icons.notifications_none_outlined,
                          ),
                          label: Text(
                            remindOn
                                ? 'Reminding'
                                : (remindAvailable
                                    ? 'Remind me'
                                    : 'Remind me (show only)'),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              if (!minimized) ...[
                ValueListenableBuilder<ChannelNowPlaying?>(
                  valueListenable: ChannelMiniPlayerManager.I.nowPlaying,
                  builder: (context, now, _) {
                    if (now == null) return const SizedBox.shrink();
                    if (!now.isPlaying) return const SizedBox.shrink();
                    final sub = (now.playlistTitle ?? '').trim().isNotEmpty
                        ? now.playlistTitle!.trim()
                        : '';
                    return Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                      child: Material(
                        color: Theme.of(context).colorScheme.surface,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: Theme.of(context)
                                .colorScheme
                                .outlineVariant
                                .withOpacity(0.6),
                          ),
                        ),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: onToggleNowPlayingExpanded,
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: Text(
                                        now.title,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                                fontWeight: FontWeight.w700),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Icon(
                                      nowPlayingExpanded
                                          ? Icons.expand_less
                                          : Icons.expand_more,
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  sub.isNotEmpty ? sub : now.title,
                                  maxLines: nowPlayingExpanded ? 6 : 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const Divider(height: 1),
              ],
              Expanded(
                child: RefreshIndicator(
                  onRefresh: onRefresh,
                  child: MediaQuery.removePadding(
                    context: context,
                    removeBottom: true,
                    child: (videos.length <= 5 && !hasNext && !loadingMore)
                        ? LayoutBuilder(
                            builder: (context, constraints) {
                              return SingleChildScrollView(
                                padding: EdgeInsets.only(bottom: listBottomPad),
                                child: ConstrainedBox(
                                  constraints: BoxConstraints(
                                    minHeight: constraints.maxHeight,
                                  ),
                                  child: IntrinsicHeight(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        ...listHeader,
                                        for (final v in videos) ...[
                                          Builder(
                                            builder: (context) {
                                              final title =
                                                  (v['title'] ?? '').toString();
                                              final thumb = thumbFromMap(v);
                                              return Column(
                                                children: [
                                                  ListTile(
                                                    dense: false,
                                                    visualDensity:
                                                        const VisualDensity(
                                                            vertical: -1),
                                                    contentPadding:
                                                        const EdgeInsets
                                                            .symmetric(
                                                            horizontal: 12),
                                                    minLeadingWidth: 0,
                                                    horizontalTitleGap: 10,
                                                    leading: ClipRRect(
                                                      borderRadius:
                                                          BorderRadius.circular(
                                                              8),
                                                      child: SizedBox(
                                                        width: 72,
                                                        height: 44,
                                                        child: thumb != null &&
                                                                thumb.isNotEmpty
                                                            ? CachedNetworkImage(
                                                                imageUrl: thumb,
                                                                fit: BoxFit
                                                                    .cover,
                                                                httpHeaders:
                                                                    authHeadersFor(
                                                                        thumb),
                                                              )
                                                            : Container(
                                                                color: Colors
                                                                    .black26),
                                                      ),
                                                    ),
                                                    title: Text(
                                                      title,
                                                      maxLines: 3,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                    ),
                                                    trailing: const Icon(Icons
                                                        .play_circle_outline),
                                                    onTap: () => onTapVideo(v),
                                                  ),
                                                  const Divider(height: 1),
                                                ],
                                              );
                                            },
                                          ),
                                        ],
                                        const Spacer(),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          )
                        : ListView.builder(
                            controller: scrollController,
                            padding: EdgeInsets.only(bottom: listBottomPad),
                            itemCount: headerCount +
                                videos.length +
                                (loadingMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index < headerCount) {
                                return listHeader[index];
                              }
                              final int vi = index - headerCount;
                              if (vi >= videos.length) {
                                return const Padding(
                                  padding: EdgeInsets.all(12.0),
                                  child: Center(
                                    child: SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
                                    ),
                                  ),
                                );
                              }
                              final v = videos[vi];
                              final title = (v['title'] ?? '').toString();
                              final thumb = thumbFromMap(v);
                              return Column(
                                children: [
                                  ListTile(
                                    dense: false,
                                    visualDensity:
                                        const VisualDensity(vertical: -1),
                                    contentPadding: const EdgeInsets.symmetric(
                                        horizontal: 12),
                                    minLeadingWidth: 0,
                                    horizontalTitleGap: 10,
                                    leading: ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: SizedBox(
                                        width: 72,
                                        height: 44,
                                        child: thumb != null && thumb.isNotEmpty
                                            ? CachedNetworkImage(
                                                imageUrl: thumb,
                                                fit: BoxFit.cover,
                                                httpHeaders:
                                                    authHeadersFor(thumb),
                                              )
                                            : Container(color: Colors.black26),
                                      ),
                                    ),
                                    title: Text(
                                      title,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    trailing:
                                        const Icon(Icons.play_circle_outline),
                                    onTap: () => onTapVideo(v),
                                  ),
                                  const Divider(height: 1),
                                ],
                              );
                            },
                          ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
