import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../channels/channel_ui_utils.dart';

class ChannelBubbles extends StatelessWidget {
  // Each map should contain: { 'name': String, 'slug': String, 'thumbUrl': String? }
  final List<Map<String, String>> channels;
  final VoidCallback? onSeeAll;
  final void Function(String slug)? onTapChannel;
  const ChannelBubbles({
    super.key,
    required this.channels,
    this.onSeeAll,
    this.onTapChannel,
  });

  // Cache the last non-empty data set for offline fallback within the session
  static List<Map<String, String>>? _lastNonEmpty;

  @override
  Widget build(BuildContext context) {
    // Prefer current data; if empty, fall back to last known non-empty set
    final List<Map<String, String>> data =
        channels.isNotEmpty ? channels : (_lastNonEmpty ?? const []);
    if (channels.isNotEmpty) {
      _lastNonEmpty = channels;
    }
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: data.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final item = data[i];
          final name = item['name'] ?? '';
          final slug = item['slug'] ?? name;
          final thumb = item['thumbUrl'];
          final fallback = Center(
            child: Text(
              (name.isNotEmpty ? name.characters.first : '?').toUpperCase(),
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          );
          return Column(
            children: [
              MouseRegion(
                cursor: onTapChannel != null
                    ? SystemMouseCursors.click
                    : MouseCursor.defer,
                child: Tooltip(
                  message: name,
                  child: Material(
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onTapChannel != null
                          ? () => onTapChannel!(slug)
                          : null,
                      customBorder: const CircleBorder(),
                      child: Ink(
                        decoration: ShapeDecoration(
                          shape: CircleBorder(
                            side: BorderSide(
                                color: Theme.of(context)
                                    .colorScheme
                                    .outlineVariant),
                          ),
                          color: Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest,
                        ),
                        width: 52,
                        height: 52,
                        child: thumb == null || thumb.isEmpty
                            ? fallback
                            : ClipOval(
                                child: CachedNetworkImage(
                                  imageUrl: thumb,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  httpHeaders: authHeadersFor(thumb),
                                  placeholder: (_, __) => fallback,
                                  errorWidget: (_, __, ___) => fallback,
                                ),
                              ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              SizedBox(
                width: 64,
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
