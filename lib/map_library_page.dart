import 'package:flutter/material.dart';

import 'offline_maps.dart';
import 'online_maps.dart';

class MapLibraryPage extends StatefulWidget {
  const MapLibraryPage({
    super.key,
    required this.store,
    required this.installedMaps,
    required this.activeMapId,
    required this.onlineMapCache,
    required this.onlineBasemap,
    required this.onMapsChanged,
    required this.onActivate,
    required this.onSelectOnlineBasemap,
  });

  final OfflineMapStore store;
  final List<InstalledMap> installedMaps;
  final String? activeMapId;
  final OnlineMapCache onlineMapCache;
  final OnlineBasemap onlineBasemap;
  final ValueChanged<List<InstalledMap>> onMapsChanged;
  final Future<void> Function(InstalledMap?) onActivate;
  final Future<void> Function(OnlineBasemap) onSelectOnlineBasemap;

  @override
  State<MapLibraryPage> createState() => _MapLibraryPageState();
}

class _MapLibraryPageState extends State<MapLibraryPage> {
  late List<InstalledMap> _installed;
  late String? _activeId;
  late OnlineBasemap _onlineBasemap;
  late Future<List<CatalogMap>> _catalog;
  late Future<Map<OnlineBasemap, int>> _cacheSizes;
  String? _downloadingId;
  double? _progress;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _installed = [...widget.installedMaps];
    _activeId = widget.activeMapId;
    _onlineBasemap = widget.onlineBasemap;
    _catalog = widget.store.fetchCatalog();
    _cacheSizes = widget.onlineMapCache.sizes();
  }

  @override
  void dispose() {
    if (_downloadingId != null) widget.store.cancelDownload();
    super.dispose();
  }

  void _refresh() {
    setState(() {
      _catalog = widget.store.fetchCatalog();
      _cacheSizes = widget.onlineMapCache.sizes();
    });
  }

  Future<void> _activate(InstalledMap map) async {
    await widget.onActivate(map);
    if (mounted) {
      setState(() {
        _activeId = map.id;
      });
    }
  }

  Future<void> _selectOnlineBasemap(OnlineBasemap basemap) async {
    await widget.onSelectOnlineBasemap(basemap);
    if (mounted) {
      setState(() {
        _activeId = null;
        _onlineBasemap = basemap;
      });
    }
  }

  Future<void> _clearCache(OnlineBasemap basemap) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Clear ${basemap.label} cache?'),
        content: const Text(
          'Previously viewed tiles for this layer will be removed from this phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.onlineMapCache.clear(basemap);
    if (!mounted) return;
    setState(() => _cacheSizes = widget.onlineMapCache.sizes());
    _message('${basemap.label} cache cleared');
  }

  Future<void> _import() async {
    try {
      final imported = await widget.store.importFromPhone(_installed);
      if (imported == null || !mounted) return;
      setState(() => _installed = [..._installed, imported]);
      widget.onMapsChanged(_installed);
      await _activate(imported);
      _message('Imported ${imported.name}');
    } catch (_) {
      _message('That MBTiles file could not be imported');
    }
  }

  Future<void> _download(CatalogMap map) async {
    setState(() {
      _downloadingId = map.id;
      _progress = null;
      _cancelRequested = false;
    });
    try {
      final installed = await widget.store.download(
        map,
        _installed,
        (value) {
          if (mounted) setState(() => _progress = value);
        },
      );
      if (!mounted) return;
      setState(() {
        _installed = [
          for (final item in _installed)
            if (item.catalogId != map.id) item,
          installed,
        ];
      });
      widget.onMapsChanged(_installed);
      await _activate(installed);
      _message('${map.name} is ready offline');
    } catch (_) {
      if (!_cancelRequested) _message('Could not download ${map.name}');
    } finally {
      if (mounted) {
        setState(() {
          _downloadingId = null;
          _progress = null;
          _cancelRequested = false;
        });
      }
    }
  }

  void _cancelDownload() {
    _cancelRequested = true;
    widget.store.cancelDownload();
  }

  Future<void> _remove(InstalledMap map) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete offline map?'),
        content: Text(
          '${map.name} will be removed from this phone. You can download or import it again later.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    if (_activeId == map.id) await _selectOnlineBasemap(_onlineBasemap);
    await widget.store.remove(map, _installed);
    if (!mounted) return;
    setState(() => _installed.removeWhere((item) => item.id == map.id));
    widget.onMapsChanged(_installed);
  }

  void _message(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Maps & layers'),
        actions: [
          IconButton(
            onPressed: _refresh,
            tooltip: 'Refresh sizes and library',
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Text('MAP ON SCREEN', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 14, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: double.infinity,
                    child: SegmentedButton<OnlineBasemap>(
                      segments: const [
                        ButtonSegment(
                          value: OnlineBasemap.street,
                          icon: Icon(Icons.map_outlined),
                          label: Text('Map'),
                        ),
                        ButtonSegment(
                          value: OnlineBasemap.satellite,
                          icon: Icon(Icons.satellite_alt_outlined),
                          label: Text('Satellite'),
                        ),
                        ButtonSegment(
                          value: OnlineBasemap.topographic,
                          icon: Icon(Icons.terrain_outlined),
                          label: Text('Topo'),
                        ),
                      ],
                      selected: _activeId == null ? {_onlineBasemap} : {},
                      emptySelectionAllowed: true,
                      showSelectedIcon: false,
                      onSelectionChanged: (selection) {
                        if (selection.isNotEmpty) {
                          _selectOnlineBasemap(selection.first);
                        }
                      },
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tiles are saved automatically as you browse. Cached areas remain visible without internet.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const Divider(height: 24),
                  FutureBuilder<Map<OnlineBasemap, int>>(
                    future: _cacheSizes,
                    builder: (context, snapshot) {
                      final sizes = snapshot.data;
                      if (sizes == null) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return Column(
                        children: [
                          for (final basemap in OnlineBasemap.values)
                            _CacheSizeRow(
                              basemap: basemap,
                              bytes: sizes[basemap] ?? 0,
                              onClear: () => _clearCache(basemap),
                            ),
                        ],
                      );
                    },
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: _refresh,
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh sizes'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Text(
                  'INSTALLED ON THIS PHONE',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ),
              TextButton.icon(
                onPressed: _downloadingId == null ? _import : null,
                icon: const Icon(Icons.file_open),
                label: const Text('Import file'),
              ),
            ],
          ),
          if (_installed.isEmpty)
            const _EmptyCard(
              icon: Icons.map_outlined,
              text: 'No offline maps installed yet.',
            )
          else
            ..._installed.map(
              (map) => Card(
                child: ListTile(
                  onTap: () => _activate(map),
                  leading: Icon(
                    _activeId == map.id
                        ? Icons.offline_pin
                        : Icons.map_outlined,
                  ),
                  title: Text(map.name),
                  subtitle: Text(
                    map.catalogId == null
                        ? 'Imported from phone'
                        : 'Downloaded from map library',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_activeId == map.id)
                        const Icon(Icons.check_circle, color: Color(0xFF26734D)),
                      IconButton(
                        onPressed: _downloadingId == null
                            ? () => _remove(map)
                            : null,
                        tooltip: 'Delete from phone',
                        icon: const Icon(Icons.delete_outline),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 24),
          Text('MAP LIBRARY', style: Theme.of(context).textTheme.labelSmall),
          const SizedBox(height: 8),
          FutureBuilder<List<CatalogMap>>(
            future: _catalog,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _EmptyCard(
                  icon: Icons.cloud_off,
                  text: 'The map library could not be reached.',
                  action: TextButton(
                    onPressed: _refresh,
                    child: const Text('Try again'),
                  ),
                );
              }
              final maps = snapshot.data ?? const [];
              if (maps.isEmpty) {
                return const _EmptyCard(
                  icon: Icons.cloud_queue,
                  text: 'The library is connected. No map packages have been published yet.',
                );
              }
              return Column(
                children: maps.map(_catalogCard).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _catalogCard(CatalogMap map) {
    final installed = _installed.any((item) => item.catalogId == map.id);
    final downloading = _downloadingId == map.id;
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    map.name,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(formatMapSize(map.sizeBytes)),
              ],
            ),
            if (map.description.isNotEmpty) ...[
              const SizedBox(height: 5),
              Text(map.description),
            ],
            if (downloading) ...[
              const SizedBox(height: 14),
              LinearProgressIndicator(value: _progress),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _cancelDownload,
                  child: const Text('Cancel'),
                ),
              ),
            ] else
              Align(
                alignment: Alignment.centerRight,
                child: installed
                    ? const Chip(
                        avatar: Icon(Icons.check, size: 18),
                        label: Text('Installed'),
                      )
                    : FilledButton.tonalIcon(
                        onPressed: _downloadingId == null
                            ? () => _download(map)
                            : null,
                        icon: const Icon(Icons.download),
                        label: const Text('Download'),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CacheSizeRow extends StatelessWidget {
  const _CacheSizeRow({
    required this.basemap,
    required this.bytes,
    required this.onClear,
  });

  final OnlineBasemap basemap;
  final int bytes;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final icon = switch (basemap) {
      OnlineBasemap.street => Icons.map_outlined,
      OnlineBasemap.satellite => Icons.satellite_alt_outlined,
      OnlineBasemap.topographic => Icons.terrain_outlined,
    };
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon, size: 21),
      title: Text('${basemap.label} cache'),
      subtitle: Text(_formatCacheSize(bytes)),
      trailing: IconButton(
        onPressed: bytes > 0 ? onClear : null,
        tooltip: 'Clear ${basemap.label} cache',
        icon: const Icon(Icons.delete_sweep_outlined),
      ),
    );
  }
}

String _formatCacheSize(int bytes) {
  if (bytes <= 0) return '0 MB';
  const kilobyte = 1024;
  const megabyte = 1024 * kilobyte;
  const gigabyte = 1024 * megabyte;
  if (bytes >= gigabyte) return '${(bytes / gigabyte).toStringAsFixed(1)} GB';
  if (bytes >= megabyte) return '${(bytes / megabyte).toStringAsFixed(1)} MB';
  if (bytes >= kilobyte) return '${(bytes / kilobyte).round()} KB';
  return '$bytes B';
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.text, this.action});

  final IconData icon;
  final String text;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Row(
          children: [
            Icon(icon),
            const SizedBox(width: 14),
            Expanded(child: Text(text)),
            ?action,
          ],
        ),
      ),
    );
  }
}
