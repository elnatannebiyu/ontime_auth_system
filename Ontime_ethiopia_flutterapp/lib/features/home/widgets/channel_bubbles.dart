import 'package:flutter/material.dart';
import '../../../api_client.dart';

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

  Map<String, String>? _authHeadersFor(String url) {
    // Only add headers for our backend origin
    if (!url.startsWith(kApiBase)) return null;
    final client = ApiClient();
    final token = client.getAccessToken();
    final tenant = client.tenant;
    final headers = <String, String>{};
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    if (tenant != null && tenant.isNotEmpty) {
      headers['X-Tenant-Id'] = tenant;
    }
    return headers.isEmpty ? null : headers;
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: channels.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          final item = channels[i];
          final name = item['name'] ?? '';
          final slug = item['slug'] ?? name;
          final thumb = item['thumbUrl'];
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
                      onTap: onTapChannel != null ? () => onTapChannel!(slug) : null,
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
                        child: thumb == null || thumb.isEmpty
                            ? Center(
                                child: Text(
                                  (name.isNotEmpty ? name.characters.first : '?').toUpperCase(),
                                  style: const TextStyle(fontWeight: FontWeight.w800),
                                ),
                              )
                            : ClipOval(
                                child: Image.network(
                                  thumb,
                                  width: 52,
                                  height: 52,
                                  fit: BoxFit.cover,
                                  headers: _authHeadersFor(thumb),
                                  errorBuilder: (_, __, ___) => Center(
                                    child: Text(
                                      (name.isNotEmpty ? name.characters.first : '?').toUpperCase(),
                                      style: const TextStyle(fontWeight: FontWeight.w800),
                                    ),
                                  ),
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
