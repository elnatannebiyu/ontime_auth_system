import 'package:flutter/material.dart';
import '../core/widgets/brand_title.dart';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key});

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  final String _version = '—';

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
            title: const Text('App name'),
            subtitle: const Text('Ontime Ethiopia'),
            leading: const Icon(Icons.apps),
          ),
          ListTile(
            title: const Text('Version'),
            subtitle: Text(_version.isEmpty ? '—' : _version),
            leading: const Icon(Icons.info_outline),
          ),
          const Divider(),
          ListTile(
            title: const Text('Contact'),
            subtitle: const Text('support@ontime.et'),
            leading: const Icon(Icons.email_outlined),
          ),
          ListTile(
            title: const Text('Website'),
            subtitle: const Text('https://aitechnologiesplc.com/'),
            leading: const Icon(Icons.public),
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
                  applicationVersion: _version),
            ),
          ),
        ],
      ),
    );
  }
}
