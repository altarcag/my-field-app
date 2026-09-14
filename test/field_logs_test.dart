import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_field_atlas_android/field_log.dart';
import 'package:my_field_atlas_android/field_projects.dart';
import 'package:my_field_atlas_android/project_export.dart';

void main() {
  final time = DateTime.utc(2026, 9, 13);
  final route = GpsTrack(
    id: 'track-1',
    startedAt: time,
    points: [
      TrackPoint(
        latitude: 40.1,
        longitude: 28.2,
        altitude: 5,
        accuracy: 3,
        capturedAt: time,
      ),
      TrackPoint(
        latitude: 40.2,
        longitude: 28.3,
        altitude: 6,
        accuracy: 3,
        capturedAt: time,
      ),
    ],
  );
  final base = FieldProject(
    id: 'project-1',
    name: 'Field & test',
    createdAt: time,
    updatedAt: time,
    tracks: [route],
  );
  FieldLog log(FieldLogKind kind, {String? photoPath}) => FieldLog(
    id: 'log-${kind.name}',
    kind: kind,
    latitude: 40.5,
    longitude: 28.6,
    title: 'Outcrop <A> & "B"',
    notes: 'Layer 1\nText ]]> & <script>',
    createdAt: time,
    photoPath: photoPath,
  );

  test(
    'legacy projects load without logs and recording preserves new logs',
    () {
      final json = base.toJson()..remove('logs');
      final legacy = FieldProject.fromJson(json);
      expect(legacy.logs, isEmpty);
      final updated = legacy.withLogs([log(FieldLogKind.text)], time);
      final recorded = updated.withTracks([route, route], time);
      expect(recorded.logs.single.title, 'Outcrop <A> & "B"');
      expect(recorded.tracks, hasLength(2));
      final roundTrip = FieldProject.fromJson(
        jsonDecode(jsonEncode(recorded.toJson())) as Map<String, Object?>,
      );
      expect(roundTrip.logs.single.toJson(), recorded.logs.single.toJson());
      expect(roundTrip.pointCount, 4);
    },
  );

  test(
    'project photo survives source deletion and export contains its bytes',
    () async {
      final dir = await Directory.systemTemp.createTemp('field-log-test-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FieldProjectStore(
        storageDirectory: Directory('${dir.path}/store'),
      );
      final source = File('${dir.path}/camera.jpg');
      final photoBytes = Uint8List.fromList([
        255,
        216,
        255,
        224,
        1,
        2,
        3,
        255,
        217,
      ]);
      await source.writeAsBytes(photoBytes);
      final storedPath = await store.importPhoto(base.id, 'photo-1', source);
      await source.delete();
      final project = base.withLogs([
        log(FieldLogKind.photo, photoPath: storedPath),
        log(FieldLogKind.waypoint),
        log(FieldLogKind.text),
      ], time);
      final other = FieldProject(
        id: 'project-2',
        name: 'Other',
        createdAt: time,
        updatedAt: time,
        tracks: const [],
      );
      await store.save([project, other], project.id);
      final restored = await FieldProjectStore(
        storageDirectory: Directory('${dir.path}/store'),
      ).load();
      expect(restored.activeProjectId, project.id);
      expect(restored.projects.last.logs, isEmpty);
      final loaded = restored.projects.first;
      expect(loaded.logs, hasLength(3));
      final kmz = await projectExportBytes(
        loaded,
        ProjectExportFormat.kmz,
        store: store,
      );
      final archive = ZipDecoder().decodeBytes(kmz);
      expect(archive.files, hasLength(2));
      final kml = utf8.decode(archive.findFile('doc.kml')!.readBytes()!);
      final photo = archive.files.singleWhere(
        (file) => file.name.startsWith('photos/'),
      );
      expect(photo.readBytes(), photoBytes);
      expect(kml, contains('src=&quot;${photo.name}&quot;'));
      expect(kml, contains('28.60000000,40.50000000'));
      expect(
        kml,
        contains('<name>Outcrop &lt;A&gt; &amp; &quot;B&quot;</name>'),
      );
      expect(kml, contains('<styleUrl>#field-text</styleUrl>'));
      expect(kml, isNot(contains(dir.path)));
      final routeOnly = utf8.decode(
        await projectExportBytes(loaded, ProjectExportFormat.kml, store: store),
      );
      expect(routeOnly, contains('<LineString>'));
      expect(routeOnly, isNot(contains('Field logs')));
      expect(routeOnly, isNot(contains('Outcrop')));
      expect(routeOnly, isNot(contains('<img')));
    },
  );

  test('KMZ exports logs without routes and rejects missing photos', () {
    final onlyLogs = base.withTracks([], time).withLogs([
      log(FieldLogKind.text),
    ], time);
    expect(onlyLogs.hasContent, isTrue);
    final archive = ZipDecoder().decodeBytes(projectToKmz(onlyLogs));
    expect(
      utf8.decode(archive.findFile('doc.kml')!.readBytes()!),
      contains('Outcrop'),
    );
    final missing = onlyLogs.withLogs([
      log(FieldLogKind.photo, photoPath: 'photos/missing.jpg'),
    ], time);
    expect(() => projectToKmz(missing), throwsStateError);
  });

  test(
    'photo recovery preserves original project, coordinates and notes',
    () async {
      final dir = await Directory.systemTemp.createTemp('field-pending-test-');
      addTearDown(() => dir.delete(recursive: true));
      final store = FieldProjectStore(storageDirectory: dir);
      final pending = PendingPhotoLog(
        projectId: base.id,
        log: log(FieldLogKind.photo),
      );
      await store.savePendingPhoto(pending);
      final loaded = await FieldProjectStore(storageDirectory: dir).loadPendingPhoto();
      expect(loaded!.toJson(), pending.toJson());
      await store.clearPendingPhoto();
      expect(await store.loadPendingPhoto(), isNull);
      await expectLater(
        store.photoFile('../outside.jpg'),
        throwsFormatException,
      );
    },
  );

  test('stop/restart track segments stay separate in both exports', () {
    final kml = projectToKml(base.withTracks([route, route], time));
    expect('<LineString>'.allMatches(kml), hasLength(2));
  });
}
