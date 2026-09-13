import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_field_atlas_android/field_projects.dart';
import 'package:my_field_atlas_android/project_export.dart';

void main() {
  final started = DateTime.utc(2026, 9, 13, 8);
  final project = FieldProject(
    id: 'project-1',
    name: 'Acıgöl & Test',
    createdAt: started,
    updatedAt: started,
    tracks: [
      GpsTrack(
        id: 'track-1',
        startedAt: started,
        endedAt: started.add(const Duration(minutes: 10)),
        points: [
          TrackPoint(
            latitude: 38.55,
            longitude: 34.51,
            altitude: 1270,
            accuracy: 3,
            capturedAt: started,
          ),
          TrackPoint(
            latitude: 38.56,
            longitude: 34.52,
            altitude: 1274,
            accuracy: 3,
            capturedAt: started.add(const Duration(minutes: 1)),
          ),
        ],
      ),
    ],
  );

  test('KML exports project and track coordinates', () {
    final kml = projectToKml(project);

    expect(kml, contains('<name>Acıgöl &amp; Test</name>'));
    expect(kml, contains('<LineString>'));
    expect(kml, contains('34.51000000,38.55000000,1270.00'));
    expect(projectFileName(project, ProjectExportFormat.kml), 'acıgöl-test.kml');
  });

  test('KMZ contains its KML as doc.kml', () {
    final archive = ZipDecoder().decodeBytes(projectToKmz(project));
    final document = archive.findFile('doc.kml');

    expect(document, isNotNull);
    expect(utf8.decode(document!.readBytes()!), contains('GPS track 1'));
  });
}
