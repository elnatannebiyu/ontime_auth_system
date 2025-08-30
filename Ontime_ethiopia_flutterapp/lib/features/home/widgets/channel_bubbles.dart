import 'package:flutter/material.dart';

class ChannelBubbles extends StatelessWidget {
  final List<String> channels;
  final VoidCallback? onSeeAll;
  final void Function(String channel)? onTapChannel;
  const ChannelBubbles({
    super.key,
    required this.channels,
    this.onSeeAll,
    this.onTapChannel,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final name = channels[i];
          return Column(
            children: [
              MouseRegion(
                cursor: onTapChannel != null ? SystemMouseCursors.click : MouseCursor.defer,
                child: Tooltip(
                  message: name,
                  child: Material(
                    shape: const CircleBorder(),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onTapChannel != null ? () => onTapChannel!(name) : null,
                      customBorder: const CircleBorder(),
                      child: Ink(
                        decoration: ShapeDecoration(
                          shape: CircleBorder(
                            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                          ),
                          color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        ),
                        width: 52,
                        height: 52,
                        child: Center(
                          child: Text(
                            name.characters.first.toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.w800),
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
