import 'package:flutter/material.dart';

class HeroCarousel extends StatefulWidget {
  final VoidCallback onPlay;
  final String liveLabel;
  final String playLabel;
  final int itemCount;
  const HeroCarousel({
    super.key,
    required this.onPlay,
    required this.liveLabel,
    required this.playLabel,
    this.itemCount = 5,
  });

  @override
  State<HeroCarousel> createState() => _HeroCarouselState();
}

class _HeroCarouselState extends State<HeroCarousel> {
  final PageController _controller = PageController(viewportFraction: .9);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 210,
          child: PageView.builder(
            controller: _controller,
            itemCount: widget.itemCount,
            onPageChanged: (i) => setState(() => _index = i),
            itemBuilder: (context, i) {
              final page = _controller.page ?? _controller.initialPage.toDouble();
              final isActive = (page - i).abs() < .5;
              return AnimatedScale(
                duration: const Duration(milliseconds: 200),
                scale: isActive ? 1 : .95,
                child: Card(
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  child: Stack(
                    children: [
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
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(999)),
                              child: Text(widget.liveLabel, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Text(
                                'Prime Story — Feature',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800),
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
                              onTap: widget.onPlay,
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
            widget.itemCount,
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
