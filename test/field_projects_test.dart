import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_field_atlas_android/field_projects.dart';

void main() {
  test('photo cleanup removes only the selected project folder', () async {
    final root = await Directory.systemTemp.createTemp('project-deletion-');
    addTearDown(() => root.delete(recursive: true));
    final store = FieldProjectStore(storageDirectory: root);
    final deletedPhoto = File('${root.path}/photos/project-1/image.jpg');
    final keptPhoto = File('${root.path}/photos/project-2/image.jpg');
    await deletedPhoto.parent.create(recursive: true);
    await keptPhoto.parent.create(recursive: true);
    await deletedPhoto.writeAsString('deleted');
    await keptPhoto.writeAsString('kept');
    await store.removeProjectPhotos('project-1');
    expect(await deletedPhoto.exists(), isFalse);
    expect(await keptPhoto.readAsString(), 'kept');
    await store.removeProjectPhotos('project-1');
    await expectLater(
      store.removeProjectPhotos('../project-2'),
      throwsFormatException,
    );
    expect(await keptPhoto.exists(), isTrue);
  });

  test('field project round-trips separate GPS track sessions', () {
    final started = DateTime.utc(2026, 9, 13, 8);
    final project = FieldProject(
      id: 'project-1',
      name: 'Acıgöl fieldwork',
      createdAt: started,
      updatedAt: started.add(const Duration(hours: 2)),
      tracks: [
        GpsTrack(
          id: 'track-1',
          startedAt: started,
          endedAt: started.add(const Duration(hours: 1)),
          points: [
            TrackPoint(
              latitude: 38.55,
              longitude: 34.51,
              altitude: 1270,
              accuracy: 3.2,
              capturedAt: started,
            ),
          ],
        ),
        GpsTrack(
          id: 'track-2',
          startedAt: started.add(const Duration(hours: 2)),
          points: const [],
        ),
      ],
    );

    final restored = FieldProject.fromJson(project.toJson());

    expect(restored.name, 'Acıgöl fieldwork');
    expect(restored.tracks, hasLength(2));
    expect(restored.pointCount, 1);
    expect(restored.tracks.first.points.first.altitude, 1270);
    expect(restored.tracks.last.id, 'track-2');
  });
}
