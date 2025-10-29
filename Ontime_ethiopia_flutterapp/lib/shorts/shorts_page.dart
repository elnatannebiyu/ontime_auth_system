import 'package:flutter/material.dart';
import '../api_client.dart';
import '../auth/tenant_auth_client.dart';
import 'shorts_player_page.dart';

class ShortsPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;

  const ShortsPage({super.key, required this.api, required this.tenantId});

  @override
  State<ShortsPage> createState() => _ShortsPageState();
}

class _ShortsPageState extends State<ShortsPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _items = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Ensure tenant is set on auth/api layer
      widget.api.setTenant(widget.tenantId);
      final client = ApiClient();
      final res = await client.get('/channels/shorts/feed/', queryParameters: {
        'limit': '50',
        'per_channel_limit': '5',
        'days': '30',
      });
      final data = res.data;
      List<Map<String, dynamic>> list;
      if (data is Map && data['results'] is List) {
        list = List<Map<String, dynamic>>.from(
            (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
      } else if (data is List) {
        list = List<Map<String, dynamic>>.from(data.map((e) => Map<String, dynamic>.from(e as Map)));
      } else {
        list = const [];
      }
      setState(() => _items = list);
    } catch (e) {
      setState(() => _error = 'Failed to load Shorts');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Retry')),
          ],
        ),
      );
    }
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.playlist_play, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('No recent shorts yet'),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Refresh')),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.separated(
        padding: const EdgeInsets.all(12),
        itemBuilder: (_, i) {
          final m = _items[i];
          final title = (m['title'] ?? '').toString();
          final channel = (m['channel'] ?? '').toString();
          final count = (m['items_count'] ?? '').toString();
          final updated = (m['updated_at'] ?? '').toString();
          return ListTile(
            leading: const Icon(Icons.play_circle_fill),
            title: Text(title.isEmpty ? '(untitled)' : title),
            subtitle: Text('Channel: $channel • Items: $count\nUpdated: $updated'),
            isThreeLine: true,
            onTap: () async {
              final playlistId = (m['playlist_id'] ?? '').toString();
              if (playlistId.isEmpty) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No playlist id found for this item')),
                  );
                }
                return;
              }
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Opening ${title.isEmpty ? 'playlist' : title} ($playlistId)...')),
                );
              }
              // Show a quick loader while fetching videos
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (_) => const Center(child: CircularProgressIndicator()),
              );
              try {
                widget.api.setTenant(widget.tenantId);
                final client = ApiClient();
                final res = await client.get('/channels/videos/', queryParameters: {
                  'playlist': playlistId,
                  'limit': '100',
                  'ordering': '-published_at',
                });
                List<Map<String, dynamic>> videos;
                final data = res.data;
                if (data is Map && data['results'] is List) {
                  videos = List<Map<String, dynamic>>.from(
                      (data['results'] as List).map((e) => Map<String, dynamic>.from(e as Map)));
                } else if (data is List) {
                  videos = List<Map<String, dynamic>>.from(
                      data.map((e) => Map<String, dynamic>.from(e as Map)));
                } else {
                  videos = const [];
                }
                if (context.mounted) Navigator.of(context).pop();
                if (videos.isEmpty) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('No videos found in this playlist')),
                    );
                  }
                  return;
                }
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Loaded ${videos.length} videos')),
                  );
                }
                if (context.mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ShortsPlayerPage(
                        videos: videos,
                        initialIndex: 0,
                      ),
                    ),
                  );
                }
              } catch (e) {
                if (context.mounted) Navigator.of(context).pop();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Failed to load playlist: $e')),
                  );
                }
              }
            },
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: _items.length,
      ),
    );
  }
}
