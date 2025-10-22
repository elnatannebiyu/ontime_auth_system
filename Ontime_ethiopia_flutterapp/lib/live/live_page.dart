import 'package:flutter/material.dart';
import '../api_client.dart';
import 'live_player_page.dart';

class LivePage extends StatefulWidget {
  const LivePage({super.key});

  @override
  State<LivePage> createState() => _LivePageState();
}

class _LivePageState extends State<LivePage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final res = await ApiClient().get('/live/');
      final raw = res.data;
      List<dynamic> data;
      if (raw is Map && raw['results'] is List) {
        data = List<dynamic>.from(raw['results'] as List);
      } else if (raw is List) {
        data = raw;
      } else {
        data = const [];
      }
      setState(() {
        _items = data.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load live streams';
      });
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Live')),
      body: RefreshIndicator(
        onRefresh: _fetch,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? Center(child: Text(_error!))
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(8),
                    itemCount: _items.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, i) {
                      final m = _items[i];
                      final title = (m['name'] ?? m['title'] ?? m['slug'] ?? '').toString();
                      final slug = (m['slug'] ?? m['id_slug'] ?? '').toString();
                      final desc = (m['description'] ?? '').toString();
                      return ListTile(
                        leading: const Icon(Icons.live_tv_outlined),
                        title: Text(title.isEmpty ? 'Live' : title),
                        subtitle: desc.isNotEmpty ? Text(desc, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
                        trailing: const Icon(Icons.play_arrow),
                        onTap: () {
                          if (slug.isEmpty) return;
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => LivePlayerPage(slug: slug),
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
