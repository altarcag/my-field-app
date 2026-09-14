import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:my_field_atlas_android/center_target.dart';
import 'package:my_field_atlas_android/field_log.dart';
import 'package:my_field_atlas_android/field_log_widgets.dart';

void main() {
  test('distance uses meters and takes the short path across the dateline', () {
    expect(distanceToMapCenter(const LatLng(0, 0), const LatLng(0, 0)), 0);
    expect(
      distanceToMapCenter(const LatLng(0, 0), const LatLng(0, 0.001)),
      closeTo(111.2, 1),
    );
    expect(
      distanceToMapCenter(const LatLng(0, 179.999), const LatLng(0, -179.999)),
      closeTo(222.4, 2),
    );
  });

  testWidgets(
    'target stays centered and distance updates when panning and GPS moves',
    (tester) async {
      final controller = MapController();
      addTearDown(controller.dispose);
      var menu = false;
      LatLng? gps = const LatLng(0, 0);
      LatLng? chosen;
      FieldLogKind? selected;
      late StateSetter update;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return FlutterMap(
                  mapController: controller,
                  options: const MapOptions(
                    initialCenter: LatLng(0, 0),
                    initialZoom: 16,
                  ),
                  children: [
                    CenterTargetLayer(
                      position: gps,
                      menuOpen: menu,
                      onToggleMenu: () => setState(() => menu = !menu),
                      onCreate: (kind, center) {
                        selected = kind;
                        chosen = center;
                      },
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      final target = find.byKey(const ValueKey('map-center-target'));
      final initialScreenPoint = tester.getCenter(target);
      expect(find.text('0 m'), findsOneWidget);
      controller.move(const LatLng(0, 0.001), 17);
      controller.rotate(40);
      await tester.pump();
      expect(tester.getCenter(target), initialScreenPoint);
      expect(find.text('111 m'), findsOneWidget);
      await tester.tap(target);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Waypoint'));
      expect(selected, FieldLogKind.waypoint);
      expect(chosen!.longitude, closeTo(0.001, 0.000001));
      update(() {
        gps = const LatLng(0, 0.001);
        menu = false;
      });
      await tester.pump();
      expect(find.text('0 m'), findsOneWidget);
      update(() => gps = null);
      await tester.pump();
      expect(find.text('Distance needs GPS'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('log dialog validates text and can reopen after dismissal', (
    tester,
  ) async {
    FieldLogDraft? draft;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                draft = await showDialog<FieldLogDraft>(
                  context: context,
                  builder: (_) => const FieldLogDialog(
                    kind: FieldLogKind.text,
                    projectName: 'Test project',
                    latitude: 40,
                    longitude: 28,
                  ),
                );
              },
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pump();
    expect(find.text('Enter a text label'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).first, 'Basalt outcrop');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(draft!.title, 'Basalt outcrop');
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(draft, isNull);
    expect(tester.takeException(), isNull);
  });
}
