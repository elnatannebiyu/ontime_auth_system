import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../core/widgets/brand_title.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    _loadVersion();
  }

  Future<void> _loadVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() {
        _version = '${info.version}+${info.buildNumber}';
      });
    } catch (_) {}
  }

  Future<void> _openEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: 'support@aitechnologiesplc.com',
      queryParameters: {
        'subject': 'Support Request',
        'body': '',
      },
    );

    try {
      await launchUrl(
        uri,
        mode: LaunchMode.platformDefault, // Works on Samsung
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No email app found on this device.'),
        ),
      );
    }
  }

  Future<void> _openWebsite() async {
    final uri = Uri.parse('https://aitechnologiesplc.com/');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the website.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(section: 'About'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ListTile(
            leading: const Icon(Icons.apps),
            title: const Text('App name'),
            subtitle: const Text('Ontime Ethiopia'),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('Version'),
            subtitle: Text(_version.isEmpty ? '—' : _version),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.email_outlined),
            title: const Text('Contact'),
            subtitle: const Text('support@aitechnologiesplc.com'),
            onTap: _openEmail,
          ),
          ListTile(
            leading: const Icon(Icons.public),
            title: const Text('Website'),
            subtitle: const Text('aitechnologiesplc.com'),
            onTap: _openWebsite,
          ),
          const Divider(),
          Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: Text(
              'Licenses',
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              title: const Text('Open source licenses'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => showLicensePage(
                context: context,
                applicationName: 'Ontime Ethiopia',
                applicationVersion: _version,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
