import 'package:flutter/material.dart';
import '../../../auth/tenant_auth_client.dart';
import '../series_service.dart';
import 'series_seasons_page.dart';
import 'series_episodes_page.dart';

class SeriesShowsPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  const SeriesShowsPage({super.key, required this.api, required this.tenantId});

  @override
  State<SeriesShowsPage> createState() => _SeriesShowsPageState();
}

class _SeriesShowsPageState extends State<SeriesShowsPage> {
  late final SeriesService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _shows = const [];

  @override
  void initState() {
    super.initState();
    _service = SeriesService(api: widget.api, tenantId: widget.tenantId);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.getShows();
      setState(() { _shows = data; });
    } catch (e) {
      setState(() { _error = 'Failed to load shows'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  Future<void> _openShow(String slug, String title) async {
    // Fetch seasons; if exactly one, push episodes directly
    try {
      final seasons = await _service.getSeasons(slug);
      if (!mounted) return;
      if (seasons.length == 1) {
        final s = seasons.first;
        final seasonId = s['id'] as int;
        final number = s['number']?.toString() ?? '';
        final rawTitle = (s['title'] as String?)?.trim() ?? '';
        final seasonTitle = rawTitle.isNotEmpty ? rawTitle : 'Season $number';
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesEpisodesPage(
              api: widget.api,
              tenantId: widget.tenantId,
              seasonId: seasonId,
              title: '$seasonTitle · $title',
            ),
          ),
        );
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => SeriesSeasonsPage(
              api: widget.api,
              tenantId: widget.tenantId,
              showSlug: slug,
              showTitle: title,
            ),
          ),
        );
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to open show')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? ListView(children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(_error!, style: const TextStyle(color: Colors.red)),
                  )
                ])
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 0.7,
                  ),
                  itemCount: _shows.length,
                  itemBuilder: (context, i) {
                    final s = _shows[i];
                    final title = (s['title'] ?? '').toString();
                    final slug = (s['slug'] ?? '').toString();
                    final cover = (s['cover_image'] ?? '').toString();
                    return _ShowCard(
                      title: title,
                      imageUrl: cover,
                      onTap: () => _openShow(slug, title),
                    );
                  },
                ),
    );
  }
}

class _ShowCard extends StatelessWidget {
  final String title;
  final String imageUrl;
  final VoidCallback? onTap;
  const _ShowCard({required this.title, required this.imageUrl, this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Card(
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: imageUrl.isNotEmpty
                  ? Image.network(imageUrl, fit: BoxFit.cover)
                  : Container(color: Colors.black12, child: const Icon(Icons.tv, size: 40)),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
