import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../auth/services/simple_session_manager.dart';

class SessionSecurityPage extends StatefulWidget {
  const SessionSecurityPage({super.key});

  @override
  State<SessionSecurityPage> createState() => _SessionSecurityPageState();
}

class _SessionSecurityPageState extends State<SessionSecurityPage> {
  final SimpleSessionManager _sessionManager = SimpleSessionManager();
  
  bool _biometricEnabled = false;
  bool _autoLockEnabled = true;
  int _autoLockMinutes = 5;
  bool _rememberDevice = true;
  bool _notifyNewLogin = true;
  
  @override
  void initState() {
    super.initState();
    _loadSettings();
  }
  
  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _biometricEnabled = prefs.getBool('biometric_enabled') ?? false;
      _autoLockEnabled = prefs.getBool('auto_lock_enabled') ?? true;
      _autoLockMinutes = prefs.getInt('auto_lock_minutes') ?? 5;
      _rememberDevice = prefs.getBool('remember_device') ?? true;
      _notifyNewLogin = prefs.getBool('notify_new_login') ?? true;
    });
  }
  
  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('biometric_enabled', _biometricEnabled);
    await prefs.setBool('auto_lock_enabled', _autoLockEnabled);
    await prefs.setInt('auto_lock_minutes', _autoLockMinutes);
    await prefs.setBool('remember_device', _rememberDevice);
    await prefs.setBool('notify_new_login', _notifyNewLogin);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Settings saved')),
      );
    }
  }
  
  Future<void> _logoutAllDevices() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout All Devices'),
        content: const Text(
          'This will log you out from all devices including this one. '
          'You will need to sign in again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Logout All'),
          ),
        ],
      ),
    );
    
    if (confirm == true) {
      await _sessionManager.logout();
      if (mounted) {
        Navigator.of(context).pushNamedAndRemoveUntil('/login', (_) => false);
      }
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session Security'),
      ),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Authentication',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Biometric Authentication'),
            subtitle: const Text('Use fingerprint or face ID to unlock'),
            value: _biometricEnabled,
            onChanged: (value) {
              setState(() {
                _biometricEnabled = value;
              });
              _saveSettings();
            },
          ),
          const Divider(),
          
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Session Settings',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('Auto-lock'),
            subtitle: Text('Lock app after $_autoLockMinutes minutes of inactivity'),
            value: _autoLockEnabled,
            onChanged: (value) {
              setState(() {
                _autoLockEnabled = value;
              });
              _saveSettings();
            },
          ),
          if (_autoLockEnabled)
            ListTile(
              title: const Text('Auto-lock timeout'),
              subtitle: Text('$_autoLockMinutes minutes'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                final minutes = await showDialog<int>(
                  context: context,
                  builder: (context) => SimpleDialog(
                    title: const Text('Select timeout'),
                    children: [1, 3, 5, 10, 15, 30]
                        .map((m) => SimpleDialogOption(
                              onPressed: () => Navigator.pop(context, m),
                              child: Text('$m minutes'),
                            ))
                        .toList(),
                  ),
                );
                if (minutes != null) {
                  setState(() {
                    _autoLockMinutes = minutes;
                  });
                  _saveSettings();
                }
              },
            ),
          SwitchListTile(
            title: const Text('Remember this device'),
            subtitle: const Text('Stay logged in on this device'),
            value: _rememberDevice,
            onChanged: (value) {
              setState(() {
                _rememberDevice = value;
              });
              _saveSettings();
            },
          ),
          const Divider(),
          
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Security Notifications',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          SwitchListTile(
            title: const Text('New login alerts'),
            subtitle: const Text('Get notified when your account is accessed from a new device'),
            value: _notifyNewLogin,
            onChanged: (value) {
              setState(() {
                _notifyNewLogin = value;
              });
              _saveSettings();
            },
          ),
          const Divider(),
          
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: Text(
              'Session Management',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: Colors.grey,
              ),
            ),
          ),
          ListTile(
            title: const Text('Active Sessions'),
            subtitle: const Text('View and manage devices'),
            leading: const Icon(Icons.devices),
            trailing: const Icon(Icons.chevron_right),
            onTap: () {
              Navigator.pushNamed(context, '/session-management');
            },
          ),
          ListTile(
            title: const Text('Logout from all devices'),
            subtitle: const Text('Sign out everywhere'),
            leading: const Icon(Icons.logout, color: Colors.red),
            onTap: _logoutAllDevices,
          ),
          const SizedBox(height: 32),
          
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Card(
              color: Theme.of(context).colorScheme.surfaceVariant,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.info_outline, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Security Tips',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    SizedBox(height: 8),
                    Text('• Enable biometric authentication for added security'),
                    Text('• Review active sessions regularly'),
                    Text('• Use a strong, unique password'),
                    Text('• Enable auto-lock when using shared devices'),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
