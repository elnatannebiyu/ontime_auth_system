import 'package:flutter/material.dart';
import '../api_client.dart';

class NotificationInboxPage extends StatefulWidget {
  const NotificationInboxPage({super.key});

  @override
  State<NotificationInboxPage> createState() => _NotificationInboxPageState();
}

class _NotificationInboxPageState extends State<NotificationInboxPage> {
  Future<Map<String, dynamic>>? _loader;
  int _page = 1;
  final int _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loader = _fetch();
  }

  Future<void> _refresh() async {
    setState(() {
      _page = 1;
      _loader = _fetch();
    });
  }

  Future<Map<String, dynamic>> _fetch() async {
    final res = await ApiClient().get('/channels/notifications/',
        queryParameters: {'page': _page, 'page_size': _pageSize});
    final data = res.data as Map<String, dynamic>;
    return data;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Notification Inbox'),
        actions: [
          IconButton(
            tooltip: 'Mark all read',
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('Mark all as read?'),
                  content: const Text('This will mark all your notifications as read.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Mark read')),
                  ],
                ),
              );
              if (ok == true) {
                try {
                  await ApiClient().post('/channels/notifications/mark-all-read/');
                } catch (_) {}
                if (mounted) _refresh();
              }
            },
            icon: const Icon(Icons.done_all_outlined),
          ),
        ],
      ),
      body: RefreshIndicator(
          onRefresh: _refresh,
          child: FutureBuilder<Map<String, dynamic>>(
            future: _loader,
            builder: (context, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Failed to load notifications'));
              }
              final data = snapshot.data ?? const {'results': []};
              final List items = (data['results'] as List? ?? []);
              if (items.isEmpty) {
                return const Center(child: Text('No notifications yet'));
              }
              return ListView.separated(
                padding: const EdgeInsets.all(12),
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final it = items[index] as Map<String, dynamic>;
                  final title = (it['title'] as String?) ?? '';
                  final body = (it['body'] as String?) ?? '';
                  final createdAt = (it['created_at'] as String?) ?? '';
                  return ListTile(
                    leading: const Icon(Icons.notifications_outlined),
                    title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(body, maxLines: 3, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 4),
                        Text(createdAt, style: Theme.of(context).textTheme.bodySmall),
                      ],
                    ),
                  );
                },
              );
            },
          )),
    );
  }
}
