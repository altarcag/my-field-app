import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import 'field_log.dart';

// Distance is geodesic, not a screen-pixel or map-projection measurement.
double distanceToMapCenter(LatLng position, LatLng center) =>
    const Distance(roundResult: false).as(LengthUnit.Meter, position, center);

String formatMapDistance(double meters) => meters < 1000
    ? '${meters.round().clamp(0, 999)} m'
    : '${(meters / 1000).toStringAsFixed(2)} km';

class CenterTargetLayer extends StatelessWidget {
  const CenterTargetLayer({
    super.key,
    required this.position,
    required this.menuOpen,
    required this.onToggleMenu,
    required this.onCreate,
    this.destination,
    this.onSetDestination,
    this.onClearDestination,
  });

  final LatLng? position;
  final LatLng? destination;
  final ValueChanged<LatLng>? onSetDestination;
  final VoidCallback? onClearDestination;
  final bool menuOpen;
  final VoidCallback onToggleMenu;
  final void Function(FieldLogKind, LatLng) onCreate;

  @override
  Widget build(BuildContext context) {
    final center = MapCamera.of(context).center;
    final origin = position;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (origin != null)
          IgnorePointer(
            child: PolylineLayer(
              polylines: [
                Polyline(
                  points: [origin, center],
                  color: const Color(0xFF1878ED),
                  strokeWidth: 3,
                  borderColor: Colors.white,
                  borderStrokeWidth: 1,
                ),
              ],
            ),
          ),
        if (destination != null) ...[
          IgnorePointer(
            child: PolylineLayer(polylines: [
              Polyline(
                points: [center, destination!],
                color: const Color(0xFFC2185B),
                strokeWidth: 3,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              ),
            ]),
          ),
          MarkerLayer(rotate: true, markers: [
            Marker(
              point: destination!,
              width: 36,
              height: 36,
              child: const Icon(Icons.flag, color: Color(0xFFC2185B), size: 30),
            ),
          ]),
          Center(
            child: IgnorePointer(
              child: Transform.translate(
                offset: const Offset(0, 64),
                child: Material(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    child: Text(
                      'Target: ${formatMapDistance(distanceToMapCenter(center, destination!))}',
                      key: const ValueKey('target-distance'),
                      style: const TextStyle(
                        color: Color(0xFFC2185B), fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
        Center(
          child: SizedBox.square(
            dimension: 48,
            child: IconButton(
              key: const ValueKey('map-center-target'),
              tooltip: 'Add a log at map center',
              onPressed: onToggleMenu,
              icon: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white,
                  border: Border.all(color: const Color(0xFF37474F), width: 3),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 3),
                  ],
                ),
              ),
            ),
          ),
        ),
        Center(
          child: IgnorePointer(
            child: Transform.translate(
              offset: const Offset(0, 38),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  child: Text(
                    origin == null
                        ? 'Distance needs GPS'
                        : '${destination == null ? '' : 'GPS: '}${formatMapDistance(distanceToMapCenter(origin, center))}',
                    key: const ValueKey('center-distance'),
                    style: const TextStyle(
                      color: Color(0xFF1565C0),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (menuOpen)
          Center(
            child: Transform.translate(
              offset: Offset(0, onSetDestination == null ? -96 : -120),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 290),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Material(
                      elevation: 6,
                      borderRadius: BorderRadius.circular(14),
                      color: Theme.of(context).colorScheme.surface,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '${center.latitude.toStringAsFixed(6)}, '
                              '${center.longitude.toStringAsFixed(6)}',
                              style: Theme.of(context).textTheme.labelMedium,
                            ),
                            if (onSetDestination != null)
                              Row(
                                children: [
                                  Expanded(
                                    child: TextButton.icon(
                                      onPressed: () => onSetDestination!(center),
                                      icon: const Icon(Icons.flag_outlined),
                                      label: const Text('Set target'),
                                    ),
                                  ),
                                  if (destination != null)
                                    IconButton(
                                      tooltip: 'Clear target',
                                      onPressed: onClearDestination,
                                      icon: const Icon(Icons.clear),
                                    ),
                                ],
                              ),
                            Row(
                              children: [
                                for (final kind in FieldLogKind.values)
                                  Expanded(
                                    child: TextButton(
                                      onPressed: () => onCreate(kind, center),
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(switch (kind) {
                                            FieldLogKind.waypoint =>
                                              Icons.add_location_alt_outlined,
                                            FieldLogKind.text =>
                                              Icons.text_fields,
                                            FieldLogKind.photo =>
                                              Icons.add_a_photo_outlined,
                                          }),
                                          const SizedBox(height: 4),
                                          Text(switch (kind) {
                                            FieldLogKind.waypoint => 'Waypoint',
                                            FieldLogKind.text => 'Text',
                                            FieldLogKind.photo => 'Photo',
                                          }),
                                        ],
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    ClipPath(
                      clipper: _BalloonTail(),
                      child: Container(
                        width: 20,
                        height: 10,
                        color: Theme.of(context).colorScheme.surface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BalloonTail extends CustomClipper<ui.Path> {
  @override
  ui.Path getClip(Size size) => ui.Path()
    ..lineTo(size.width, 0)
    ..lineTo(size.width / 2, size.height)
    ..close();

  @override
  bool shouldReclip(_BalloonTail oldClipper) => false;
}
