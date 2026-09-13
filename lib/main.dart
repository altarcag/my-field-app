import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import 'field_projects.dart';
import 'map_library_page.dart';
import 'offline_maps.dart';
import 'online_maps.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final onlineMapCache = OnlineMapCache();
  await onlineMapCache.initialize();
  runApp(FieldApp(onlineMapCache: onlineMapCache));
}

class FieldApp extends StatelessWidget {
  const FieldApp({super.key, required this.onlineMapCache});

  final OnlineMapCache onlineMapCache;

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
      home: MapScreen(onlineMapCache: onlineMapCache),
    );
  }
}

class MapScreen extends StatefulWidget {
  const MapScreen({super.key, required this.onlineMapCache});

  final OnlineMapCache onlineMapCache;

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  static const LatLng _turkeyCenter = LatLng(39.0, 35.0);

  final MapController _mapController = MapController();
  final ValueNotifier<double> _mapRotation = ValueNotifier(0);
  final OfflineMapStore _offlineMaps = OfflineMapStore();
  final FieldProjectStore _fieldProjectStore = FieldProjectStore();
  StreamSubscription<Position>? _positionSubscription;
  Timer? _trackSaveTimer;

  Position? _position;
  String _locationStatus = 'Starting GPS…';
  bool _isLocating = true;
  bool _didCenterOnFirstFix = false;

  List<FieldProject> _projects = [];
  String? _activeProjectId;
  String? _activeTrackId;
  bool _isLoadingProjects = true;
  bool _isRecording = false;

  List<InstalledMap> _installedMaps = [];
  InstalledMap? _activeOfflineMap;
  MbTilesTileProvider? _offlineTileProvider;
  OnlineBasemap _onlineBasemap = OnlineBasemap.street;
  late CachedTileProvider _onlineTileProvider;
  bool _isLoadingMaps = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _onlineTileProvider = widget.onlineMapCache.providerFor(_onlineBasemap);
    _startLocation();
    _restoreMaps();
    _restoreProjects();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _trackSaveTimer?.cancel();
    if (!_isLoadingProjects) unawaited(_saveProjects());
    _positionSubscription?.cancel();
    _offlineTileProvider?.dispose();
    _onlineTileProvider.dispose();
    _mapRotation.dispose();
    _mapController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(_saveProjects());
    }
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
    _recordPosition(position);
    if (!_didCenterOnFirstFix) {
      _didCenterOnFirstFix = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _centerOnPosition();
      });
    }
  }

  FieldProject? get _activeProject {
    for (final project in _projects) {
      if (project.id == _activeProjectId) return project;
    }
    return null;
  }

  Future<void> _restoreProjects() async {
    final state = await _fieldProjectStore.load();
    if (!mounted) return;
    setState(() {
      _projects = state.projects;
      _activeProjectId = state.activeProjectId;
      _isLoadingProjects = false;
    });
  }

  Future<void> _saveProjects() =>
      _fieldProjectStore.save(_projects, _activeProjectId);

  TrackPoint _trackPoint(Position position) => TrackPoint(
    latitude: position.latitude,
    longitude: position.longitude,
    altitude: position.altitude,
    accuracy: position.accuracy,
    capturedAt: DateTime.now().toUtc(),
  );

  void _recordPosition(Position position) {
    if (!_isRecording || _activeProjectId == null || _activeTrackId == null) {
      return;
    }
    final projectIndex = _projects.indexWhere(
      (project) => project.id == _activeProjectId,
    );
    if (projectIndex < 0) return;
    final project = _projects[projectIndex];
    final trackIndex = project.tracks.indexWhere(
      (track) => track.id == _activeTrackId,
    );
    if (trackIndex < 0) return;

    final track = project.tracks[trackIndex];
    final candidate = _trackPoint(position);
    if (track.points.isNotEmpty) {
      final previous = track.points.last;
      final elapsed = candidate.capturedAt.difference(previous.capturedAt);
      final distance = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        candidate.latitude,
        candidate.longitude,
      );
      if (elapsed < const Duration(seconds: 2) ||
          (distance < 2 && elapsed < const Duration(seconds: 10))) {
        return;
      }
    }

    final now = candidate.capturedAt;
    final updatedTracks = [...project.tracks];
    updatedTracks[trackIndex] = track.addPoint(candidate);
    final updatedProjects = [..._projects];
    updatedProjects[projectIndex] = project.withTracks(updatedTracks, now);
    setState(() => _projects = updatedProjects);
    _trackSaveTimer?.cancel();
    _trackSaveTimer = Timer(
      const Duration(seconds: 2),
      () => unawaited(_saveProjects()),
    );
  }

  Future<void> _toggleRecording() async {
    if (_isRecording) {
      await _stopRecording();
      return;
    }
    if (_activeProject == null) {
      await _openProjectPicker();
      if (_activeProject == null) return;
    }

    final projectIndex = _projects.indexWhere(
      (project) => project.id == _activeProjectId,
    );
    if (projectIndex < 0) return;
    final now = DateTime.now().toUtc();
    final track = GpsTrack(
      id: 'track-${now.microsecondsSinceEpoch}',
      startedAt: now,
      points: [if (_position != null) _trackPoint(_position!)],
    );
    final project = _projects[projectIndex];
    final updatedProjects = [..._projects];
    updatedProjects[projectIndex] = project.withTracks(
      [...project.tracks, track],
      now,
    );
    setState(() {
      _projects = updatedProjects;
      _activeTrackId = track.id;
      _isRecording = true;
    });
    await _saveProjects();
  }

  Future<void> _stopRecording() async {
    final projectIndex = _projects.indexWhere(
      (project) => project.id == _activeProjectId,
    );
    final now = DateTime.now().toUtc();
    if (projectIndex >= 0 && _activeTrackId != null) {
      final project = _projects[projectIndex];
      final trackIndex = project.tracks.indexWhere(
        (track) => track.id == _activeTrackId,
      );
      if (trackIndex >= 0) {
        final updatedTracks = [...project.tracks];
        updatedTracks[trackIndex] = updatedTracks[trackIndex].finish(now);
        final updatedProjects = [..._projects];
        updatedProjects[projectIndex] = project.withTracks(updatedTracks, now);
        setState(() => _projects = updatedProjects);
      }
    }
    _trackSaveTimer?.cancel();
    setState(() {
      _activeTrackId = null;
      _isRecording = false;
    });
    await _saveProjects();
  }

  Future<void> _selectProject(String id) async {
    if (_isRecording) await _stopRecording();
    if (!mounted) return;
    setState(() => _activeProjectId = id);
    await _saveProjects();
  }

  Future<void> _createProject() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New field project'),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Project name',
            hintText: 'Cappadocia — September 2026',
          ),
          onSubmitted: (value) {
            final trimmed = value.trim();
            if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final trimmed = controller.text.trim();
              if (trimmed.isNotEmpty) Navigator.pop(context, trimmed);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || !mounted) return;
    if (_isRecording) await _stopRecording();
    final now = DateTime.now().toUtc();
    final project = FieldProject(
      id: 'project-${now.microsecondsSinceEpoch}',
      name: name,
      createdAt: now,
      updatedAt: now,
      tracks: const [],
    );
    setState(() {
      _projects = [..._projects, project];
      _activeProjectId = project.id;
    });
    await _saveProjects();
  }

  Future<void> _openProjectPicker() async {
    final createNew = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Field projects',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                  FilledButton.icon(
                    onPressed: () => Navigator.pop(sheetContext, true),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('New'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              if (_projects.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 30),
                  child: Text('Create a project before recording a GPS track.'),
                )
              else
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _projects.length,
                    itemBuilder: (context, index) {
                      final project = _projects[index];
                      final selected = project.id == _activeProjectId;
                      return ListTile(
                        leading: Icon(
                          selected ? Icons.folder : Icons.folder_outlined,
                        ),
                        title: Text(project.name),
                        subtitle: Text(
                          '${project.tracks.length} tracks · '
                          '${project.pointCount} GPS points',
                        ),
                        trailing: selected ? const Icon(Icons.check) : null,
                        onTap: () {
                          Navigator.pop(sheetContext);
                          unawaited(_selectProject(project.id));
                        },
                      );
                    },
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    if (createNew == true && mounted) await _createProject();
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
    final onlineBasemap = await widget.onlineMapCache.getSelected();
    InstalledMap? active;
    for (final map in maps) {
      if (map.id == activeId) active = map;
    }

    if (!mounted) return;
    final oldOnlineProvider = _onlineTileProvider;
    setState(() {
      _installedMaps = maps;
      _onlineBasemap = onlineBasemap;
      _onlineTileProvider = widget.onlineMapCache.providerFor(onlineBasemap);
      _isLoadingMaps = false;
    });
    oldOnlineProvider.dispose();
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
    if (!mounted) return;
    final oldProvider = _onlineTileProvider;
    setState(() {
      _onlineBasemap = basemap;
      _onlineTileProvider = widget.onlineMapCache.providerFor(basemap);
    });
    oldProvider.dispose();
    await widget.onlineMapCache.setSelected(basemap);
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
          onlineMapCache: widget.onlineMapCache,
          onlineBasemap: _onlineBasemap,
          onMapsChanged: _mapsChanged,
          onActivate: _activateMap,
          onSelectOnlineBasemap: _selectOnlineBasemap,
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
    return TileLayer(
      key: ValueKey(_onlineBasemap.id),
      urlTemplate: _onlineBasemap.urlTemplate,
      tileProvider: _onlineTileProvider,
      userAgentPackageName: 'com.altarcag.my_field_atlas_android',
      maxNativeZoom: _onlineBasemap.maxNativeZoom,
    );
  }

  String get _attributionText {
    final offlineAttribution = _activeOfflineMap?.attribution;
    if (offlineAttribution != null) return offlineAttribution;
    return _onlineBasemap.attribution;
  }

  @override
  Widget build(BuildContext context) {
    final position = _position;
    final activeProject = _activeProject;
    final point = position == null
        ? null
        : LatLng(position.latitude, position.longitude);

    return Scaffold(
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: _turkeyCenter,
              initialZoom: 5.5,
              minZoom: 2,
              maxZoom: 22,
              interactionOptions: const InteractionOptions(
                enableMultiFingerGestureRace: true,
                rotationThreshold: 30,
                rotationWinGestures:
                    MultiFingerGesture.rotate |
                    MultiFingerGesture.pinchZoom |
                    MultiFingerGesture.pinchMove,
              ),
              onPositionChanged: (camera, _) {
                if ((_mapRotation.value - camera.rotation).abs() > 0.05) {
                  _mapRotation.value = camera.rotation;
                }
              },
            ),
            children: [
              _buildBaseMap(),
              if (activeProject != null)
                PolylineLayer(
                  polylines: [
                    for (final track in activeProject.tracks)
                      if (track.points.length > 1)
                        Polyline(
                          points: [
                            for (final point in track.points)
                              LatLng(point.latitude, point.longitude),
                          ],
                          color: const Color(0xFF9A3655),
                          strokeWidth: 4,
                          borderColor: Colors.white,
                          borderStrokeWidth: 1.5,
                        ),
                  ],
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
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: _NorthControl(
                rotation: _mapRotation,
                onPressed: () => _mapController.rotate(0),
              ),
            ),
          ),
          Positioned(
            left: 12,
            bottom: 12,
            child: SafeArea(
              child: _ProjectTrackingControl(
                project: activeProject,
                isLoading: _isLoadingProjects,
                isRecording: _isRecording,
                onProjects: _openProjectPicker,
                onToggleRecording: _toggleRecording,
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
            tooltip: 'Maps and layers',
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

class _ProjectTrackingControl extends StatelessWidget {
  const _ProjectTrackingControl({
    required this.project,
    required this.isLoading,
    required this.isRecording,
    required this.onProjects,
    required this.onToggleRecording,
  });

  final FieldProject? project;
  final bool isLoading;
  final bool isRecording;
  final VoidCallback onProjects;
  final VoidCallback onToggleRecording;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      elevation: 4,
      color: colors.surface.withValues(alpha: 0.96),
      borderRadius: BorderRadius.circular(18),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 290),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: InkWell(
                  onTap: onProjects,
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          project == null
                              ? Icons.create_new_folder_outlined
                              : Icons.folder_open,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                isLoading
                                    ? 'Loading projects…'
                                    : project?.name ?? 'Choose a project',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.labelLarge,
                              ),
                              if (!isLoading)
                                Text(
                                  project == null
                                      ? 'Required for route logging'
                                      : '${project!.tracks.length} tracks · '
                                            '${project!.pointCount} points',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 4),
                        const Icon(Icons.expand_less, size: 18),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              FilledButton.icon(
                onPressed: isLoading ? null : onToggleRecording,
                style: FilledButton.styleFrom(
                  minimumSize: const Size(0, 46),
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  backgroundColor: isRecording
                      ? colors.error
                      : colors.primary,
                ),
                icon: Icon(
                  isRecording ? Icons.stop_rounded : Icons.route_outlined,
                  size: 20,
                ),
                label: Text(isRecording ? 'Stop' : 'Record'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NorthControl extends StatelessWidget {
  const _NorthControl({
    required this.rotation,
    required this.onPressed,
  });

  final ValueNotifier<double> rotation;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return ValueListenableBuilder<double>(
      valueListenable: rotation,
      builder: (context, degrees, _) {
        final isNorthUp = degrees.abs() < 0.1;
        return Tooltip(
          message: isNorthUp ? 'Map is pointing north' : 'Reset north',
          child: Material(
            color: colors.surface.withValues(alpha: 0.96),
            elevation: 3,
            shadowColor: Colors.black26,
            shape: CircleBorder(
              side: BorderSide(color: colors.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onPressed,
              customBorder: const CircleBorder(),
              child: Semantics(
                button: true,
                label: isNorthUp ? 'Map is pointing north' : 'Reset map north',
                child: SizedBox.square(
                  dimension: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Positioned(
                        top: 5,
                        child: Text(
                          'N',
                          style: TextStyle(
                            color: colors.primary,
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            height: 1,
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 7),
                        child: Transform.rotate(
                          angle: -degrees * math.pi / 180,
                          child: const CustomPaint(
                            size: Size.square(25),
                            painter: _CompassNeedlePainter(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _CompassNeedlePainter extends CustomPainter {
  const _CompassNeedlePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final north = ui.Path()
      ..moveTo(center.dx, 1)
      ..lineTo(center.dx + 4.5, center.dy)
      ..lineTo(center.dx - 4.5, center.dy)
      ..close();
    final south = ui.Path()
      ..moveTo(center.dx, size.height - 1)
      ..lineTo(center.dx + 4.5, center.dy)
      ..lineTo(center.dx - 4.5, center.dy)
      ..close();

    canvas.drawPath(north, Paint()..color = const Color(0xFF9A3655));
    canvas.drawPath(south, Paint()..color = const Color(0xFF66717C));
    canvas.drawCircle(center, 2.1, Paint()..color = Colors.white);
    canvas.drawCircle(
      center,
      1.15,
      Paint()..color = const Color(0xFF35424D),
    );
  }

  @override
  bool shouldRepaint(covariant _CompassNeedlePainter oldDelegate) => false;
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
