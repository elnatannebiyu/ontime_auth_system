import 'package:flutter/material.dart';
import '../auth/tenant_auth_client.dart';
import '../channels/channels_page.dart';
import '../core/localization/l10n.dart';
import '../features/home/widgets/hero_carousel.dart';
import '../features/home/widgets/section_header.dart';
import '../features/home/widgets/poster_row.dart';
import '../features/home/widgets/mini_player_bar.dart';
import '../features/home/widgets/channel_bubbles.dart';
import '../core/widgets/brand_title.dart';

// Overflow menu actions for Home AppBar
enum _HomeMenuAction { profile, settings, about, switchLanguage }

class HomePage extends StatefulWidget {
  final AuthApi api;
  final TokenStore tokenStore;
  final String tenantId;
  final LocalizationController localizationController;

  const HomePage({
    super.key,
    required this.api,
    required this.tokenStore,
    required this.tenantId,
    required this.localizationController,
  });

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Map<String, dynamic>? _me;
  bool _loading = true;
  String? _error;

  // Lightweight language toggle (session only)
  // Localization is now centralized

  String _t(String key) => widget.localizationController.t(key);

  // Simple demo data for enhanced sections (UI-only)
  static const List<String> _demoChannels = [
    'Abbay',
    'ESAT',
    'Kana',
    'Zete',
    'Arts',
    'Music',
    'Sport',
    'Kids'
  ];

  // Mini player state
  bool _showMini = false;

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
      final me = await widget.api.me();
      setState(() {
        _me = me;
      });
    } catch (e) {
      setState(() {
        _error = 'Failed to load profile';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  // (_logout removed – not used on Home streaming UI)

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.localizationController,
      builder: (_, __) => DefaultTabController(
        length: 4,
        child: Scaffold(
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => setState(() => _showMini = true),
            icon: const Icon(Icons.live_tv),
            label: Text(_t('go_live')),
          ),
          appBar: AppBar(
            title: const BrandTitle(),
            bottom: TabBar(
              labelPadding: const EdgeInsets.symmetric(horizontal: 12),
              isScrollable: true,
              tabs: [
                Tab(text: _t('for_you')),
                Tab(text: _t('trending')),
                Tab(text: _t('sports')),
                Tab(text: _t('kids')),
              ],
            ),
            actions: [
              IconButton(
                tooltip: 'Search',
                icon: const Icon(Icons.search),
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Search coming soon')),
                  );
                },
              ),
              PopupMenuButton<_HomeMenuAction>(
                tooltip: 'Menu',
                itemBuilder: (context) {
                  final lang = widget.localizationController.language;
                  final switchTo = lang == AppLanguage.en ? 'AM' : 'EN';
                  return <PopupMenuEntry<_HomeMenuAction>>[
                    PopupMenuItem(
                      value: _HomeMenuAction.profile,
                      child: ListTile(
                        leading: const Icon(Icons.account_circle_outlined),
                        title: Text(_t('profile')),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _HomeMenuAction.settings,
                      child: ListTile(
                        leading: const Icon(Icons.settings_outlined),
                        title: Text(_t('settings')),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    PopupMenuItem(
                      value: _HomeMenuAction.about,
                      child: ListTile(
                        leading: const Icon(Icons.info_outline),
                        title: Text(_t('about')),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _HomeMenuAction.switchLanguage,
                      child: ListTile(
                        leading: const Icon(Icons.translate),
                        title: Text('${_t('switch_language')} ($switchTo)'),
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                      ),
                    ),
                  ];
                },
                onSelected: (value) {
                  switch (value) {
                    case _HomeMenuAction.profile:
                      Navigator.of(context).pushNamed('/profile');
                      break;
                    case _HomeMenuAction.settings:
                      Navigator.of(context).pushNamed('/settings');
                      break;
                    case _HomeMenuAction.about:
                      Navigator.of(context).pushNamed('/about');
                      break;
                    case _HomeMenuAction.switchLanguage:
                      widget.localizationController.toggleLanguage();
                      break;
                  }
                },
              ),
            ],
          ),
          body: TabBarView(
            children: [
              // For You tab
              _buildForYou(context),
              // Other tabs placeholder UI for now
              _buildPlaceholderTab(context, _t('trending')),
              _buildPlaceholderTab(context, _t('sports')),
              _buildPlaceholderTab(context, _t('kids')),
            ],
          ),
          // Mini-player (extracted widget)
          bottomSheet: _showMini
              ? MiniPlayerBar(
                  nowPlayingLabel: _t('now_playing'),
                  onClose: () => setState(() => _showMini = false),
                )
              : null,
        ),
      ),
    );
  }

  // For You main content with pull-to-refresh
  Widget _buildForYou(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _load,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Text(_error!, style: const TextStyle(color: Colors.red))
                    : _me == null
                        ? const Text('No data')
                        : SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                // Hero carousel (extracted)
                                HeroCarousel(
                                  liveLabel: _t('live'),
                                  playLabel: _t('play'),
                                  onPlay: () =>
                                      setState(() => _showMini = true),
                                ),
                                const SizedBox(height: 12),
                                // Browse Channels section header (extracted)
                                SectionHeader(
                                  title: _t('browse_channels'),
                                  actionLabel: _t('see_all'),
                                  onAction: _loading
                                      ? null
                                      : () async {
                                          await Navigator.of(context).push(
                                            MaterialPageRoute(
                                              builder: (_) =>
                                                  const ChannelsPage(
                                                      tenantId: 'ontime'),
                                            ),
                                          );
                                          widget.api.setTenant(widget.tenantId);
                                        },
                                ),
                                ChannelBubbles(
                                  channels: _demoChannels,
                                  onSeeAll: null,
                                  onTapChannel: (_) {},
                                ),
                                const SizedBox(height: 12),
                                // Trending Now section (extracted header)
                                SectionHeader(title: _t('trending_now')),
                                const SizedBox(height: 8),
                                const PosterRow(count: 10),
                                const SizedBox(height: 16),
                                // New Releases section (extracted header)
                                SectionHeader(title: _t('new_releases')),
                                const SizedBox(height: 8),
                                const PosterRow(count: 12, tall: true),
                                const SizedBox(
                                    height:
                                        70), // space for mini-player above FAB notch
                              ],
                            ),
                          ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderTab(BuildContext context, String title) {
    return Center(
      child: Text('$title — coming soon',
          style: Theme.of(context).textTheme.titleMedium),
    );
  }
}
