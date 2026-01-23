// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../api_client.dart';
import 'dart:async';

class HeroCarousel extends StatefulWidget {
  final VoidCallback onPlay;
  final String liveLabel;
  final String playLabel;
  final List<Map<String, dynamic>> items;
  final void Function(Map<String, dynamic> item)? onTapShow;
  const HeroCarousel({
    super.key,
    required this.onPlay,
    required this.liveLabel,
    required this.playLabel,
    this.items = const [],
    this.onTapShow,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _controller = PageController(viewportFraction: .9);
  int _index = 0;
  Timer? _autoTimer;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
    _startAutoRotate();
  }

  @override
  void dispose() {
    _autoTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _startAutoRotate() {
    _autoTimer?.cancel();
    if (!mounted) return;
    _autoTimer = Timer.periodic(const Duration(seconds: 6), (timer) {
      if (!mounted || !(_controller.hasClients)) return;
      final total = widget.items.isNotEmpty ? widget.items.length : 5;
      if (total <= 1) return;
      final currentPage =
          _controller.page ?? _controller.initialPage.toDouble();
      int nextPage = (currentPage.round() + 1) % total;
      _controller.animateToPage(
        nextPage,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    Map<String, String>? authHeadersFor(String url) {
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

    final hasItems = widget.items.isNotEmpty;
    final itemCount = hasItems ? widget.items.length : 5;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 210,
          child: PageView.builder(
            controller: _controller,
            itemCount: itemCount,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final item = hasItems && i < widget.items.length
                  ? widget.items[i]
                  : const <String, dynamic>{};
              final title = (item['title'] ?? 'Featured Story').toString();
              final imageUrl = (item['cover_image'] ?? '').toString();
              final channelName =
                  (item['channel_name'] ?? '').toString().trim();
              final page =
                  _controller.page ?? _controller.initialPage.toDouble();
              final isActive = (page - i).abs() < .5;
              return AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: isActive ? 1 : .95,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20)),
                  child: Stack(
                    children: [
                      if (imageUrl.isNotEmpty)
                        Positioned.fill(
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            httpHeaders: authHeadersFor(imageUrl),
                            errorWidget: (context, _, __) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                      Positioned.fill(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.blueGrey.withOpacity(.25),
                                Colors.black.withOpacity(.15),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        left: 12,
                        right: 12,
                        bottom: 12,
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                  color: Colors.red,
                                  borderRadius: BorderRadius.circular(999)),
                              child: Text(
                                  channelName.isNotEmpty
                                      ? channelName
                                      : widget.liveLabel,
                                  style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton.tonalIcon(
                              onPressed: widget.onPlay,
                              icon: const Icon(Icons.play_arrow),
                              label: Text(widget.playLabel),
                            ),
                          ],
                        ),
                      ),
                      Positioned.fill(
                        child: Material(
                          color: Colors.transparent,
                          child: Semantics(
                            label: 'Hero item',
                            button: true,
                            child: InkWell(
                              onTap: () {
                                if (widget.onTapShow != null && hasItems) {
                                  widget.onTapShow!(item);
                                } else {
                                  widget.onPlay();
                                }
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            itemCount,
            (i) => AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: i == _index ? 18 : 6,
              height: 6,
              decoration: BoxDecoration(
                color: i == _index
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(999),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
