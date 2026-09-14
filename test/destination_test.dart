import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_field_atlas_android/center_target.dart';

void main() {
  testWidgets('target menu and both distances respond to map movement', (tester) async {
    final controller = MapController();
    addTearDown(controller.dispose);
    LatLng? selected;
    var cleared = false;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: FlutterMap(
      mapController: controller,
      options: const MapOptions(initialCenter: LatLng(0, 0), initialZoom: 16),
      children: [
        CenterTargetLayer(
          position: const LatLng(0, -0.001),
          destination: const LatLng(0, 0.002),
          menuOpen: true,
          onToggleMenu: () {},
          onCreate: (_, _) {},
          onSetDestination: (point) => selected = point,
          onClearDestination: () => cleared = true,
        ),
      ],
    ))));
    expect(find.text('GPS: 111 m'), findsOneWidget);
    expect(find.text('Target: 222 m'), findsOneWidget);
    await tester.tap(find.text('Set target'));
    expect(selected, const LatLng(0, 0));
    controller.move(const LatLng(0, 0.001), 16);
    await tester.pumpAndSettle();
    expect(find.text('GPS: 222 m'), findsOneWidget);
    expect(find.text('Target: 111 m'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear target'));
    expect(cleared, isTrue);
    expect(tester.takeException(), isNull);
  });
}
