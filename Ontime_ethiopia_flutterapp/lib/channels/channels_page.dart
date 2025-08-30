import 'package:flutter/material.dart';
import '../api_client.dart';
import '../core/widgets/brand_title.dart';

class ChannelsPage extends StatefulWidget {
  final String tenantId;
  const ChannelsPage({super.key, required this.tenantId});

  @override
  State<ChannelsPage> createState() => _ChannelsPageState();
}

class _ChannelsPageState extends State<ChannelsPage> {
  final ApiClient _client = ApiClient();
  bool _loading = true;
  String? _error;
  List<dynamic> _channels = const [];
  final Map<String, List<dynamic>> _playlistsByChannel = {};
  final Map<String, List<dynamic>> _videosByPlaylist = {};
  final Set<String> _expandedChannels = <String>{};

  @override
  void initState() {
    super.initState();
    _client.setTenant(widget.tenantId);
    _loadChannels();
  }

  Future<void> _loadChannels({bool clearCaches = false}) async {
    if (clearCaches) {
      setState(() {
        _playlistsByChannel.clear();
        _videosByPlaylist.clear();
      });
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      // Fetch all pages so the user can see/select any active channel
      final List<dynamic> all = [];
      int page = 1;
      while (true) {
        final res = await _client.get('/channels/', queryParameters: {
          'ordering': 'sort_order',
          'page': page.toString(),
        });
        final raw = res.data;
        List<dynamic> pageData;
        if (raw is Map && raw['results'] is List) {
          pageData = List<dynamic>.from(raw['results'] as List);
        } else if (raw is List) {
          pageData = raw;
        } else {
          pageData = const [];
        }
        all.addAll(pageData);
        // Stop if not paginated or no next page
        if (raw is! Map || raw['next'] == null) {
          break;
        }
        page += 1;
      }
      setState(() {
        _channels = all;
      });
      // After channels reload, for any channels currently expanded,
      // force-clear and re-fetch their playlists so UI shows fresh data
      for (final slug in _expandedChannels) {
        _playlistsByChannel.remove(slug);
        await _ensurePlaylists(slug);
      }
    } catch (e) {
      setState(() {
        _error = 'Failed to load channels';
      });
    } finally {
      setState(() {
        _loading = false;
      });
    }
  }

  Future<void> _ensurePlaylists(String channelSlug) async {
    if (_playlistsByChannel.containsKey(channelSlug)) return;
    try {
      final res = await _client.get('/channels/playlists/', queryParameters: {
        'channel': channelSlug,
        'is_active': 'true',
      });
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
        _playlistsByChannel[channelSlug] = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load playlists')),
      );
    }
  }

  Future<void> _ensureVideos(String playlistId) async {
    if (_videosByPlaylist.containsKey(playlistId)) return;
    try {
      final res = await _client.get('/channels/videos/', queryParameters: {
        'playlist': playlistId,
      });
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
        _videosByPlaylist[playlistId] = data;
      });
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Failed to load videos')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const BrandTitle(section: 'Channels'),
        actions: [
          IconButton(
            onPressed: _loading ? null : () => _loadChannels(clearCaches: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
              : RefreshIndicator(
                  onRefresh: () => _loadChannels(clearCaches: true),
                  child: ListView.builder(
                      itemCount: _channels.length,
                      itemBuilder: (context, index) {
                        final ch = _channels[index] as Map<String, dynamic>;
                        final slug = (ch['id_slug'] ?? '').toString();
                        final title = (ch['name_en'] ?? ch['name_am'] ?? slug).toString();
                        final isActive = ch['is_active'] == true;
                        return ExpansionTile(
                          key: PageStorageKey('ch:$slug'),
                          title: Text(title),
                          subtitle: Text(slug + (isActive ? '' : ' (inactive)')),
                          initiallyExpanded: _expandedChannels.contains(slug),
                          onExpansionChanged: (expanded) {
                            setState(() {
                              if (expanded) {
                                _expandedChannels.add(slug);
                              } else {
                                _expandedChannels.remove(slug);
                              }
                            });
                          },
                          trailing: IconButton(
                            tooltip: 'Refresh playlists',
                            icon: const Icon(Icons.refresh),
                            onPressed: () async {
                              setState(() {
                                _playlistsByChannel.remove(slug);
                                _videosByPlaylist.clear(); // clear dependent videos cache
                              });
                              await _ensurePlaylists(slug);
                            },
                          ),
                          children: [
                            FutureBuilder(
                              future: _ensurePlaylists(slug),
                              builder: (context, snapshot) {
                                final playlists = _playlistsByChannel[slug];
                                if (playlists == null) {
                                  return const Padding(
                                    padding: EdgeInsets.all(12),
                                    child: LinearProgressIndicator(),
                                  );
                                }
                                if (playlists.isEmpty) {
                                  return const ListTile(title: Text('No playlists'));
                                }
                                return Column(
                                  children: playlists.map((pl) {
                                    final p = pl as Map<String, dynamic>;
                                    final pid = (p['id'] ?? '').toString();
                                    final ptitle = (p['title'] ?? pid).toString();
                                    return ExpansionTile(
                                      key: PageStorageKey('pl:$pid'),
                                      title: Text(ptitle),
                                      children: [
                                        FutureBuilder(
                                          future: _ensureVideos(pid),
                                          builder: (context, snapshot) {
                                            final vids = _videosByPlaylist[pid];
                                            if (vids == null) {
                                              return const Padding(
                                                padding: EdgeInsets.all(12),
                                                child: LinearProgressIndicator(),
                                              );
                                            }
                                            if (vids.isEmpty) {
                                              return const ListTile(title: Text('No videos'));
                                            }
                                            return Column(
                                              children: vids.map((v) {
                                                final vv = v as Map<String, dynamic>;
                                                final vid = (vv['video_id'] ?? '').toString();
                                                final vtitle = (vv['title'] ?? vid).toString();
                                                return ListTile(
                                                  dense: true,
                                                  leading: const Icon(Icons.play_circle_fill),
                                                  title: Text(vtitle),
                                                  subtitle: Text(vid),
                                                );
                                              }).toList(),
                                            );
                                          },
                                        ),
                                      ],
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        );
                      },
                  ),
                ),
    );
  }
}
