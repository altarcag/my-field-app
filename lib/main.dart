import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'map_library_page.dart';
import 'offline_maps.dart';

enum OnlineBasemap { street, satellite, topographic }

void main() {
  runApp(const FieldApp());
}

class FieldApp extends StatelessWidget {
  const FieldApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Field App',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF315C45),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const MapScreen(),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const LatLng _turkeyCenter = LatLng(39.0, 35.0);

  final MapController _mapController = MapController();
  final OfflineMapStore _offlineMaps = OfflineMapStore();
  StreamSubscription<Position>? _positionSubscription;

  Position? _position;
  String _locationStatus = 'Starting GPS…';
  bool _isLocating = true;
  bool _didCenterOnFirstFix = false;

  List<InstalledMap> _installedMaps = [];
  InstalledMap? _activeOfflineMap;
  MbTilesTileProvider? _offlineTileProvider;
  OnlineBasemap _onlineBasemap = OnlineBasemap.street;
  bool _isLoadingMaps = true;

  @override
  void initState() {
    super.initState();
    _startLocation();
    _restoreMaps();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
    _offlineTileProvider?.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _startLocation() async {
    await _positionSubscription?.cancel();
    if (mounted) {
      setState(() {
        _isLocating = true;
        _locationStatus = 'Checking location access…';
      });
    }

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      _setLocationError('Phone location is switched off');
      return;
    }

    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied) {
      _setLocationError('Location permission was not granted');
      return;
    }
    if (permission == LocationPermission.deniedForever) {
      _setLocationError('Location permission is blocked in Android settings');
      return;
    }

    if (mounted) {
      setState(() {
        _isLocating = true;
        _locationStatus = 'Waiting for a precise GPS fix…';
      });
    }

    const settings = LocationSettings(
      accuracy: LocationAccuracy.bestForNavigation,
      distanceFilter: 0,
    );
    _positionSubscription = Geolocator.getPositionStream(
      locationSettings: settings,
    ).listen(
      _handlePosition,
      onError: (Object error) => _setLocationError('GPS error: $error'),
    );
  }

  void _handlePosition(Position position) {
    if (!mounted) return;
    setState(() {
      _position = position;
      _isLocating = false;
      _locationStatus = 'GPS active';
    });
    if (!_didCenterOnFirstFix) {
      _didCenterOnFirstFix = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerOnPosition();
      });
    }
  }

  void _setLocationError(String message) {
    if (!mounted) return;
    setState(() {
      _isLocating = false;
      _locationStatus = message;
    });
  }

  void _centerOnPosition() {
    final position = _position;
    if (position == null) {
      _startLocation();
      return;
    }
    final currentZoom = _mapController.camera.zoom;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      currentZoom < 16 ? 16.0 : currentZoom,
    );
  }

  Future<void> _openRelevantSettings() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _restoreMaps() async {
    final maps = await _offlineMaps.load();
    final activeId = await _offlineMaps.getActiveId();
    InstalledMap? active;
    for (final map in maps) {
      if (map.id == activeId) active = map;
    }

    if (!mounted) return;
    setState(() {
      _installedMaps = maps;
      _isLoadingMaps = false;
    });
    if (active != null) await _activateMap(active, persist: false);
  }

  Future<void> _activateMap(
    InstalledMap? map, {
    bool persist = true,
  }) async {
    MbTilesTileProvider? provider;
    if (map != null) {
      try {
        provider = MbTilesTileProvider.fromPath(path: map.filePath);
        provider.mbtiles.getMetadata();
      } catch (_) {
        provider?.dispose();
        if (mounted) _showMessage('Could not open ${map.name}');
        return;
      }
    }

    final oldProvider = _offlineTileProvider;
    if (mounted) {
      setState(() {
        _offlineTileProvider = provider;
        _activeOfflineMap = map;
      });
    } else {
      provider?.dispose();
      return;
    }
    oldProvider?.dispose();
    if (persist) await _offlineMaps.setActiveId(map?.id);
  }

  Future<void> _selectOnlineBasemap(OnlineBasemap basemap) async {
    await _activateMap(null);
    if (mounted) setState(() => _onlineBasemap = basemap);
  }

  void _mapsChanged(List<InstalledMap> maps) {
    if (mounted) setState(() => _installedMaps = [...maps]);
  }

  Future<void> _openMapLibrary() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (context) => MapLibraryPage(
          store: _offlineMaps,
          installedMaps: _installedMaps,
          activeMapId: _activeOfflineMap?.id,
          onlineStreetMapSelected:
              _activeOfflineMap == null && _onlineBasemap == OnlineBasemap.street,
          onMapsChanged: _mapsChanged,
          onActivate: _activateMap,
          onSelectOnlineStreetMap: () =>
              _selectOnlineBasemap(OnlineBasemap.street),
        ),
      ),
    );
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  TileLayer _buildBaseMap() {
    final provider = _offlineTileProvider;
    if (_activeOfflineMap != null && provider != null) {
      return TileLayer(
        key: ValueKey(_activeOfflineMap!.id),
        tileProvider: provider,
        maxNativeZoom: 22,
      );
    }
    if (_onlineBasemap == OnlineBasemap.satellite) {
      return TileLayer(
        key: const ValueKey('esri-world-imagery'),
        urlTemplate:
            'https://server.arcgisonline.com/ArcGIS/rest/services/'
            'World_Imagery/MapServer/tile/{z}/{y}/{x}',
        userAgentPackageName: 'com.altarcag.my_field_atlas_android',
        maxNativeZoom: 19,
      );
    }
    if (_onlineBasemap == OnlineBasemap.topographic) {
      return TileLayer(
        key: const ValueKey('opentopomap'),
        urlTemplate: 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.altarcag.my_field_atlas_android',
        maxNativeZoom: 17,
      );
    }
    return TileLayer(
      key: const ValueKey('openstreetmap'),
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.altarcag.my_field_atlas_android',
      maxNativeZoom: 19,
    );
  }

  String get _attributionText {
    final offlineAttribution = _activeOfflineMap?.attribution;
    if (offlineAttribution != null) return offlineAttribution;
    return switch (_onlineBasemap) {
      OnlineBasemap.street => '© OpenStreetMap contributors',
      OnlineBasemap.satellite => 'Imagery © Esri and contributors',
      OnlineBasemap.topographic =>
        '© OpenTopoMap · © OpenStreetMap contributors',
    };
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final point = position == null
        ? null
        : LatLng(position.latitude, position.longitude);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: const MapOptions(
              initialCenter: _turkeyCenter,
              initialZoom: 5.5,
              minZoom: 2,
              maxZoom: 22,
            ),
            children: [
              _buildBaseMap(),
              if (point != null) ...[
                CircleLayer(
                  circles: [
                    CircleMarker(
                      point: point,
                      radius: position!.accuracy,
                      useRadiusInMeter: true,
                      color: const Color(0x263156C8),
                      borderColor: const Color(0x803156C8),
                      borderStrokeWidth: 1,
                    ),
                  ],
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 34,
                      height: 34,
                      child: const _LocationMarker(),
                    ),
                  ],
                ),
              ],
            ],
          ),
          Positioned(
            right: 8,
            bottom: 6,
            child: _Attribution(text: _attributionText),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: _StatusPanel(
                position: position,
                status: _locationStatus,
                isLocating: _isLocating,
                onRetry: _startLocation,
                onSettings: _openRelevantSettings,
              ),
            ),
          ),
          SafeArea(
            child: Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(top: 84, right: 12),
                child: _BasemapSwitcher(
                  selected: _activeOfflineMap == null
                      ? _onlineBasemap
                      : null,
                  onSelected: _selectOnlineBasemap,
                ),
              ),
            ),
          ),
          if (_isLoadingMaps)
            const Positioned(
              left: 0,
              right: 0,
              bottom: 20,
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'map-library',
            onPressed: _openMapLibrary,
            tooltip: 'Offline maps',
            child: Icon(
              _activeOfflineMap == null
                  ? Icons.layers_outlined
                  : Icons.offline_pin,
            ),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'my-location',
            onPressed: _centerOnPosition,
            tooltip: 'Centre on my location',
            child: Icon(
              position == null ? Icons.gps_not_fixed : Icons.my_location,
            ),
          ),
        ],
      ),
    );
  }
}

class _BasemapSwitcher extends StatelessWidget {
  const _BasemapSwitcher({
    required this.selected,
    required this.onSelected,
  });

  final OnlineBasemap? selected;
  final ValueChanged<OnlineBasemap> onSelected;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      color: Colors.white.withValues(alpha: 0.94),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _BasemapButton(
            icon: Icons.map_outlined,
            label: 'Map',
            selected: selected == OnlineBasemap.street,
            onPressed: () => onSelected(OnlineBasemap.street),
          ),
          _BasemapButton(
            icon: Icons.satellite_alt_outlined,
            label: 'Satellite',
            selected: selected == OnlineBasemap.satellite,
            onPressed: () => onSelected(OnlineBasemap.satellite),
          ),
          _BasemapButton(
            icon: Icons.terrain_outlined,
            label: 'Topo',
            selected: selected == OnlineBasemap.topographic,
            onPressed: () => onSelected(OnlineBasemap.topographic),
          ),
        ],
      ),
    );
  }
}

class _BasemapButton extends StatelessWidget {
  const _BasemapButton({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
        color: selected ? colorScheme.secondaryContainer : Colors.transparent,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 18),
            const SizedBox(width: 5),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _LocationMarker extends StatelessWidget {
  const _LocationMarker();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: const Color(0xFF3156C8),
        border: Border.all(color: Colors.white, width: 4),
        boxShadow: const [
          BoxShadow(
            color: Color(0x55000000),
            blurRadius: 6,
            offset: Offset(0, 2),
          ),
        ],
      ),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({
    required this.position,
    required this.status,
    required this.isLocating,
    required this.onRetry,
    required this.onSettings,
  });

  final Position? position;
  final String status;
  final bool isLocating;
  final VoidCallback onRetry;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(16),
      color: Colors.white.withValues(alpha: 0.94),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 11, 10, 11),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isLocating)
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            else
              Icon(
                position == null ? Icons.gps_off : Icons.gps_fixed,
                size: 20,
                color: position == null
                    ? Theme.of(context).colorScheme.error
                    : const Color(0xFF26734D),
              ),
            const SizedBox(width: 10),
            Flexible(
              child: position == null
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          status,
                          style: Theme.of(context).textTheme.labelLarge,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Tap retry or check Android settings',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    )
                  : _PositionReadout(position: position!),
            ),
            if (position == null && !isLocating) ...[
              IconButton(
                onPressed: onRetry,
                tooltip: 'Retry',
                icon: const Icon(Icons.refresh),
              ),
              IconButton(
                onPressed: onSettings,
                tooltip: 'Location settings',
                icon: const Icon(Icons.settings),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PositionReadout extends StatelessWidget {
  const _PositionReadout({required this.position});

  final Position position;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '${position.latitude.toStringAsFixed(6)}, '
          '${position.longitude.toStringAsFixed(6)}',
          style: textTheme.labelLarge?.copyWith(
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '±${position.accuracy.toStringAsFixed(1)} m   '
          'Altitude ${position.altitude.toStringAsFixed(1)} m',
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(text, style: const TextStyle(fontSize: 10)),
      ),
    );
  }
}
