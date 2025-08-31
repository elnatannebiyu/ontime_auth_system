import 'package:flutter/material.dart';
import '../api_client.dart';

class SessionManagementPage extends StatefulWidget {
  const SessionManagementPage({super.key});

  @override
  State<SessionManagementPage> createState() => _SessionManagementPageState();
}

class _SessionManagementPageState extends State<SessionManagementPage> {
  final ApiClient _apiClient = ApiClient();
  List<Map<String, dynamic>> _sessions = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final response = await _apiClient.get('/sessions/');
      setState(() {
        _sessions = List<Map<String, dynamic>>.from(
          response.data['sessions'] ?? [],
        );
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load sessions';
        _loading = false;
      });
    }
  }

  Future<void> _revokeSession(String sessionId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Revoke Session'),
        content: const Text('Are you sure you want to revoke this session?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Revoke'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await _apiClient.delete('/sessions/$sessionId/');
      await _loadSessions();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Session revoked successfully')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to revoke session')),
        );
      }
    }
  }

  Widget _buildSessionTile(Map<String, dynamic> session) {
    final isCurrentSession = session['is_current'] == true;
    final deviceInfo = session['device_info'] ?? {};
    final lastActive = session['last_activity'];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isCurrentSession ? Colors.green : Colors.grey,
          child: Icon(
            _getDeviceIcon(deviceInfo['device_type']),
            color: Colors.white,
          ),
        ),
        title: Text(
          '${deviceInfo['device_name'] ?? 'Unknown Device'}',
          style: TextStyle(
            fontWeight: isCurrentSession ? FontWeight.bold : FontWeight.normal,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isCurrentSession)
              const Text(
                'Current Session',
                style: TextStyle(color: Colors.green, fontWeight: FontWeight.w500),
              ),
            Text('${deviceInfo['os_name'] ?? ''} ${deviceInfo['os_version'] ?? ''}'),
            Text('Last active: ${_formatDate(lastActive)}'),
            Text('IP: ${session['ip_address'] ?? 'Unknown'}'),
          ],
        ),
        trailing: !isCurrentSession
            ? IconButton(
                icon: const Icon(Icons.logout, color: Colors.red),
                onPressed: () => _revokeSession(session['id']),
                tooltip: 'Revoke Session',
              )
            : null,
      ),
    );
  }

  IconData _getDeviceIcon(String? deviceType) {
    switch (deviceType?.toLowerCase()) {
      case 'mobile':
      case 'phone':
        return Icons.phone_android;
      case 'tablet':
        return Icons.tablet;
      case 'desktop':
      case 'web':
        return Icons.computer;
      default:
        return Icons.devices;
    }
  }

  String _formatDate(String? dateStr) {
    if (dateStr == null) return 'Unknown';
    try {
      final date = DateTime.parse(dateStr);
      final now = DateTime.now();
      final diff = now.difference(date);

      if (diff.inMinutes < 1) return 'Just now';
      if (diff.inMinutes < 60) return '${diff.inMinutes} minutes ago';
      if (diff.inHours < 24) return '${diff.inHours} hours ago';
      if (diff.inDays < 7) return '${diff.inDays} days ago';
      
      return '${date.day}/${date.month}/${date.year}';
    } catch (e) {
      return dateStr;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Active Sessions'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSessions,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.error_outline, size: 64, color: Colors.red),
                      const SizedBox(height: 16),
                      Text(_error!),
                      const SizedBox(height: 16),
                      FilledButton(
                        onPressed: _loadSessions,
                        child: const Text('Retry'),
                      ),
                    ],
                  ),
                )
              : _sessions.isEmpty
                  ? const Center(
                      child: Text('No active sessions'),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadSessions,
                      child: ListView.builder(
                        itemCount: _sessions.length,
                        itemBuilder: (context, index) {
                          return _buildSessionTile(_sessions[index]);
                        },
                      ),
                    ),
    );
  }
}
