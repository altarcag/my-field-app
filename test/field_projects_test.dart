import 'package:flutter_test/flutter_test.dart';
import 'package:my_field_atlas_android/field_projects.dart';

void main() {
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
