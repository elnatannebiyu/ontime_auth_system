import 'package:flutter/material.dart';
import '../api_client.dart';
import '../auth/tenant_auth_client.dart';
import 'shorts_player_page.dart';

class ShortsPlaylistPage extends StatefulWidget {
  final AuthApi api;
  final String tenantId;
  final String playlistId;
  final String title;

  const ShortsPlaylistPage({
    super.key,
    required this.api,
    required this.tenantId,
    required this.playlistId,
    required this.title,
  });

  @override
  State<ShortsPlaylistPage> createState() => _ShortsPlaylistPageState();
}

class _ShortsPlaylistPageState extends State<ShortsPlaylistPage> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _videos = const [];

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
      widget.api.setTenant(widget.tenantId);
      final client = ApiClient();
      final res = await client.get('/channels/videos/', queryParameters: {
        'playlist': widget.playlistId,
        'limit': '100',
        'ordering': '-published_at',
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
      setState(() => _videos = list);
    } catch (e) {
      setState(() => _error = 'Failed to load videos');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title.isEmpty ? 'Shorts' : widget.title)),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
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
    if (_videos.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.ondemand_video, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('No videos found'),
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
          final m = _videos[i];
          final title = (m['title'] ?? '').toString();
          final vid = (m['video_id'] ?? '').toString();
          final published = (m['published_at'] ?? '').toString();
          return ListTile(
            leading: const Icon(Icons.play_arrow_rounded),
            title: Text(title.isEmpty ? vid : title),
            subtitle: Text(published),
            onTap: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ShortsPlayerPage(
                    videos: _videos,
                    initialIndex: i,
                  ),
                ),
              );
            },
          );
        },
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemCount: _videos.length,
      ),
    );
  }
}
