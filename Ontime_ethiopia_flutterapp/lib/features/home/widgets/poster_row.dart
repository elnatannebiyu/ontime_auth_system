import 'package:flutter/material.dart';

class PosterRow extends StatelessWidget {
  final int count;
  final bool tall;
  const PosterRow({super.key, this.count = 8, this.tall = false});

  @override
  Widget build(BuildContext context) {
    final size = tall ? const Size(120, 180) : const Size(140, 90);
    return SizedBox(
      // Poster height + spacing + approx. one-line title height + small padding
      height: size.height + 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (_, i) {
          return _PosterTile(size: size, title: 'Title');
        },
      ),
    );
  }
}

class _PosterTile extends StatefulWidget {
  final Size size;
  final String title;
  const _PosterTile({required this.size, required this.title});

  @override
  State<_PosterTile> createState() => _PosterTileState();
}

class _PosterTileState extends State<_PosterTile> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          label: '${widget.title} poster',
          button: true,
          child: AnimatedScale(
            duration: const Duration(milliseconds: 120),
            scale: _pressed ? 0.98 : 1,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTapDown: (_) => setState(() => _pressed = true),
                onTapCancel: () => setState(() => _pressed = false),
                onTap: () => setState(() => _pressed = false),
                borderRadius: BorderRadius.circular(12),
                child: Ink(
                  width: widget.size.width,
                  height: widget.size.height,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 10,
                        offset: const Offset(0, 6),
                      )
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Stack(
                      children: [
                        Positioned.fill(child: Container(color: Colors.black26)),
                        Positioned.fill(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.transparent,
                                  Colors.black.withOpacity(.35),
                                ],
                              ),
                            ),
                          ),
                        ),
                        const Center(
                          child: Icon(Icons.play_circle_fill, size: 36, color: Colors.white70),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: widget.size.width,
          child: Text(
            widget.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
