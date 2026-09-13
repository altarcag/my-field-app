import 'package:flutter/material.dart';

import 'offline_maps.dart';

class MapLibraryPage extends StatefulWidget {
  const MapLibraryPage({
    super.key,
    required this.store,
    required this.installedMaps,
    required this.activeMapId,
    required this.onMapsChanged,
    required this.onActivate,
  });

  final OfflineMapStore store;
  final List<InstalledMap> installedMaps;
  final String? activeMapId;
  final ValueChanged<List<InstalledMap>> onMapsChanged;
  final Future<void> Function(InstalledMap?) onActivate;

  @override
  State<MapLibraryPage> createState() => _MapLibraryPageState();
}

class _MapLibraryPageState extends State<MapLibraryPage> {
  late List<InstalledMap> _installed;
  late String? _activeId;
  late Future<List<CatalogMap>> _catalog;
  String? _downloadingId;
  double? _progress;
  bool _cancelRequested = false;

  @override
  void initState() {
    super.initState();
    _installed = [...widget.installedMaps];
    _activeId = widget.activeMapId;
    _catalog = widget.store.fetchCatalog();
  }

  @override
  void dispose() {
    if (_downloadingId != null) widget.store.cancelDownload();
    super.dispose();
  }

  void _refreshCatalog() {
    setState(() => _catalog = widget.store.fetchCatalog());
  }

  Future<void> _activate(InstalledMap? map) async {
    await widget.onActivate(map);
    if (mounted) setState(() => _activeId = map?.id);
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

    if (_activeId == map.id) await _activate(null);
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
        title: const Text('Offline maps'),
        actions: [
          IconButton(
            onPressed: _refreshCatalog,
            tooltip: 'Refresh library',
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
            child: ListTile(
              onTap: () => _activate(null),
              leading: const Icon(Icons.public),
              title: const Text('OpenStreetMap'),
              subtitle: const Text('Online · previously viewed areas are cached'),
              trailing: _activeId == null
                  ? const Icon(Icons.check_circle, color: Color(0xFF26734D))
                  : null,
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
                    onPressed: _refreshCatalog,
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
            if (action != null) action!,
          ],
        ),
      ),
    );
  }
}
