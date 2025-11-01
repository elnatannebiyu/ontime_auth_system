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
      final res = await client.get('/channels/shorts/ready/feed/', queryParameters: {
        'limit': '50',
        'recent_bias_count': '15',
      });
      final data = res.data;
      final List<Map<String, dynamic>> list = data is List
          ? List<Map<String, dynamic>>.from(
              data.map((e) => Map<String, dynamic>.from(e as Map)))
          : (data is Map && data['results'] is List)
              ? List<Map<String, dynamic>>.from((data['results'] as List)
                  .map((e) => Map<String, dynamic>.from(e as Map)))
              : const [];
      setState(() => _items = list);
    } catch (e) {
      setState(() => _error = 'Failed to load Shorts');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
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
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.motion_photos_paused_outlined, size: 48, color: Colors.grey),
            const SizedBox(height: 8),
            const Text('No recent shorts yet'),
            const SizedBox(height: 8),
            TextButton(onPressed: _load, child: const Text('Refresh')),
          ],
        ),
      );
    }
    // Directly render the shorts player with the feed items (no playlist selection)
    return ShortsPlayerPage(videos: _items, initialIndex: 0);
  }
}
