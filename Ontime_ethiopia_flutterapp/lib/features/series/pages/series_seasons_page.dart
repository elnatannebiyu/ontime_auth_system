import 'package:flutter/material.dart';
import '../../../auth/tenant_auth_client.dart';
import '../series_service.dart';
import 'series_episodes_page.dart';

class SeriesSeasonsPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final String showSlug;
  final String showTitle;
  const SeriesSeasonsPage({
    super.key,
    required this.api,
    required this.tenantId,
    required this.showSlug,
    required this.showTitle,
  });

  @override
  State<SeriesSeasonsPage> createState() => _SeriesSeasonsPageState();
}

class _SeriesSeasonsPageState extends State<SeriesSeasonsPage> {
  late final SeriesService _service;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _seasons = const [];

  @override
  void initState() {
    super.initState();
    _service = SeriesService(api: widget.api, tenantId: widget.tenantId);
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final data = await _service.getSeasons(widget.showSlug);
      setState(() { _seasons = data; });
    } catch (e) {
      setState(() { _error = 'Failed to load seasons'; });
    } finally {
      setState(() { _loading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.showTitle)),
      body: RefreshIndicator(
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
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _seasons.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) {
                      final s = _seasons[i];
                      final id = s['id'] as int;
                      final number = s['number']?.toString() ?? '';
                      final title = (s['title'] as String?)?.trim();
                      final display = (title != null && title.isNotEmpty) ? title : 'Season $number';
                      final cover = (s['cover_image'] ?? '').toString();
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        leading: cover.isNotEmpty
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(8),
                                child: Image.network(cover, width: 56, height: 56, fit: BoxFit.cover),
                              )
                            : const CircleAvatar(child: Icon(Icons.tv))
                                ,
                        title: Text(display),
                        subtitle: Text('S$number'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => SeriesEpisodesPage(
                                api: widget.api,
                                tenantId: widget.tenantId,
                                seasonId: id,
                                title: '$display · ${widget.showTitle}',
                                coverImage: cover,
                              ),
                            ),
                          );
                        },
                      );
                    },
                  ),
      ),
    );
  }
}
