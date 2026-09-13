import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  static const String _offlinePathKey = 'offline_map_path';
  static const String _offlineNameKey = 'offline_map_name';
  static const String _offlineSelectedKey = 'offline_map_selected';

  final MapController _mapController = MapController();
  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  StreamSubscription<Position>? _positionSubscription;

  Position? _position;
  String _locationStatus = 'Starting GPS…';
  bool _isLocating = true;
  bool _didCenterOnFirstFix = false;

  MbTilesTileProvider? _offlineTileProvider;
  String? _offlineMapPath;
  String? _offlineMapName;
  bool _useOfflineMap = false;
  bool _isImportingMap = false;

  @override
  void initState() {
    super.initState();
    _startLocation();
    _restoreOfflineMap();
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
      onError: (Object error) {
        _setLocationError('GPS error: $error');
      },
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
    final targetZoom = currentZoom < 16 ? 16.0 : currentZoom;
    _mapController.move(
      LatLng(position.latitude, position.longitude),
      targetZoom,
    );
  }

  Future<void> _openRelevantSettings() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _restoreOfflineMap() async {
    final savedPath = await _preferences.getString(_offlinePathKey);
    if (savedPath == null || !await File(savedPath).exists()) return;

    try {
      final provider = MbTilesTileProvider.fromPath(path: savedPath);
      final name =
          await _preferences.getString(_offlineNameKey) ??
          path.basename(savedPath);
      final selected =
          await _preferences.getBool(_offlineSelectedKey) ?? false;

      if (!mounted) {
        provider.dispose();
        return;
      }

      setState(() {
        _offlineTileProvider = provider;
        _offlineMapPath = savedPath;
        _offlineMapName = name;
        _useOfflineMap = selected;
      });
    } catch (_) {
      await _preferences.remove(_offlinePathKey);
      await _preferences.remove(_offlineNameKey);
      await _preferences.remove(_offlineSelectedKey);
    }
  }

  Future<void> _importMbTiles() async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['mbtiles'],
    );
    if (selected == null) return;

    if (mounted) {
      setState(() => _isImportingMap = true);
    }

    File? temporaryFile;
    try {
      final documents = await getApplicationDocumentsDirectory();
      final mapsDirectory = Directory(
        path.join(documents.path, 'offline_maps'),
      );
      await mapsDirectory.create(recursive: true);

      final safeName = selected.name.replaceAll(
        RegExp(r'[^A-Za-z0-9._-]'),
        '_',
      );
      final destination = File(path.join(mapsDirectory.path, safeName));
      temporaryFile = File('${destination.path}.importing');

      if (await temporaryFile.exists()) {
        await temporaryFile.delete();
      }

      final output = temporaryFile.openWrite();
      await output.addStream(selected.readAsByteStream());
      await output.close();

      final validator = MbTilesTileProvider.fromPath(
        path: temporaryFile.path,
      );
      validator.mbtiles.getMetadata();
      validator.dispose();

      _offlineTileProvider?.dispose();
      if (await destination.exists()) {
        await destination.delete();
      }
      await temporaryFile.rename(destination.path);

      final provider = MbTilesTileProvider.fromPath(
        path: destination.path,
      );

      await _preferences.setString(_offlinePathKey, destination.path);
      await _preferences.setString(_offlineNameKey, selected.name);
      await _preferences.setBool(_offlineSelectedKey, true);

      if (!mounted) {
        provider.dispose();
        return;
      }

      setState(() {
        _offlineTileProvider = provider;
        _offlineMapPath = destination.path;
        _offlineMapName = selected.name;
        _useOfflineMap = true;
      });
      _showMessage('Offline map imported: ${selected.name}');
    } catch (error) {
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      _showMessage('Could not import that MBTiles file');
    } finally {
      if (mounted) {
        setState(() => _isImportingMap = false);
      }
    }
  }

  Future<void> _selectOnlineMap() async {
    await _preferences.setBool(_offlineSelectedKey, false);
    if (mounted) {
      setState(() => _useOfflineMap = false);
    }
  }

  Future<void> _selectOfflineMap() async {
    if (_offlineTileProvider == null) {
      await _importMbTiles();
      return;
    }

    await _preferences.setBool(_offlineSelectedKey, true);
    if (mounted) {
      setState(() => _useOfflineMap = true);
    }
  }

  Future<void> _removeOfflineMap() async {
    final mapPath = _offlineMapPath;
    if (mapPath == null) return;

    _offlineTileProvider?.dispose();
    if (mounted) {
      setState(() {
        _offlineTileProvider = null;
        _offlineMapPath = null;
        _offlineMapName = null;
        _useOfflineMap = false;
      });
    }

    await _preferences.remove(_offlinePathKey);
    await _preferences.remove(_offlineNameKey);
    await _preferences.remove(_offlineSelectedKey);

    final mapFile = File(mapPath);
    if (await mapFile.exists()) {
      await mapFile.delete();
    }
    _showMessage('Offline map removed');
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _showMapLayers() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const ListTile(
                  title: Text(
                    'Map layers',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Previously viewed online tiles are cached automatically.',
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.public),
                  title: const Text('OpenStreetMap'),
                  subtitle: const Text('Online map with browse caching'),
                  trailing: !_useOfflineMap
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _selectOnlineMap();
                  },
                ),
                if (_offlineTileProvider != null)
                  ListTile(
                    leading: const Icon(Icons.offline_pin),
                    title: Text(_offlineMapName ?? 'Imported offline map'),
                    subtitle: const Text('MBTiles · fully offline'),
                    trailing: _useOfflineMap
                        ? const Icon(Icons.check_circle)
                        : null,
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _selectOfflineMap();
                    },
                  ),
                ListTile(
                  leading: const Icon(Icons.file_open),
                  title: const Text('Import MBTiles'),
                  subtitle: const Text('Copy an offline map onto this phone'),
                  onTap: () {
                    Navigator.pop(sheetContext);
                    _importMbTiles();
                  },
                ),
                if (_offlineTileProvider != null)
                  ListTile(
                    leading: Icon(
                      Icons.delete_outline,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    title: Text(
                      'Remove imported map',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(sheetContext);
                      _removeOfflineMap();
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  TileLayer _buildBaseMap() {
    if (_useOfflineMap && _offlineTileProvider != null) {
      return TileLayer(
        key: ValueKey(_offlineMapPath),
        tileProvider: _offlineTileProvider!,
        maxNativeZoom: 22,
      );
    }

    return TileLayer(
      key: const ValueKey('openstreetmap'),
      urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      userAgentPackageName: 'com.altarcag.my_field_atlas_android',
      maxNativeZoom: 19,
    );
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
            child: _Attribution(
              text: _useOfflineMap
                  ? 'Offline · ${_offlineMapName ?? 'MBTiles'}'
                  : '© OpenStreetMap contributors',
            ),
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
          if (_isImportingMap)
            const ColoredBox(
              color: Color(0x33000000),
              child: Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(20),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text('Importing offline map…'),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingActionButton.small(
            heroTag: 'map-layers',
            onPressed: _showMapLayers,
            tooltip: 'Map layers',
            child: Icon(
              _useOfflineMap ? Icons.offline_pin : Icons.layers_outlined,
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
