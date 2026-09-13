import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

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
  StreamSubscription<Position>? _positionSubscription;

  Position? _position;
  String _locationStatus = 'Starting GPS…';
  bool _isLocating = true;
  bool _didCenterOnFirstFix = false;

  @override
  void initState() {
    super.initState();
    _startLocation();
  }

  @override
  void dispose() {
    _positionSubscription?.cancel();
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
              maxZoom: 19,
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.altarcag.my_field_atlas_android',
                maxNativeZoom: 19,
              ),
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
          const Positioned(
            right: 8,
            bottom: 6,
            child: _Attribution(),
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
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _centerOnPosition,
        tooltip: 'Centre on my location',
        child: Icon(position == null ? Icons.gps_not_fixed : Icons.my_location),
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
  const _Attribution();

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Padding(
        padding: EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        child: Text(
          '© OpenStreetMap contributors',
          style: TextStyle(fontSize: 10),
        ),
      ),
    );
  }
}
