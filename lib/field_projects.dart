import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

class TrackPoint {
  const TrackPoint({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    required this.capturedAt,
  });

  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final DateTime capturedAt;

  Map<String, Object> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'altitude': altitude,
    'accuracy': accuracy,
    'capturedAt': capturedAt.toUtc().toIso8601String(),
  };

  factory TrackPoint.fromJson(Map<String, Object?> json) => TrackPoint(
    latitude: (json['latitude']! as num).toDouble(),
    longitude: (json['longitude']! as num).toDouble(),
    altitude: (json['altitude']! as num).toDouble(),
    accuracy: (json['accuracy']! as num).toDouble(),
    capturedAt: DateTime.parse(json['capturedAt']! as String),
  );
}

class GpsTrack {
  const GpsTrack({
    required this.id,
    required this.startedAt,
    required this.points,
    this.endedAt,
  });

  final String id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final List<TrackPoint> points;

  GpsTrack addPoint(TrackPoint point) => GpsTrack(
    id: id,
    startedAt: startedAt,
    endedAt: endedAt,
    points: [...points, point],
  );

  GpsTrack finish(DateTime time) => GpsTrack(
    id: id,
    startedAt: startedAt,
    endedAt: time,
    points: points,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt?.toUtc().toIso8601String(),
    'points': points.map((point) => point.toJson()).toList(),
  };

  factory GpsTrack.fromJson(Map<String, Object?> json) => GpsTrack(
    id: json['id']! as String,
    startedAt: DateTime.parse(json['startedAt']! as String),
    endedAt: json['endedAt'] == null
        ? null
        : DateTime.parse(json['endedAt']! as String),
    points: (json['points'] as List<Object?>? ?? const [])
        .map(
          (point) => TrackPoint.fromJson(
            (point! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(),
  );
}

class FieldProject {
  const FieldProject({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.tracks,
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<GpsTrack> tracks;

  int get pointCount =>
      tracks.fold(0, (total, track) => total + track.points.length);

  FieldProject withTracks(List<GpsTrack> value, DateTime time) => FieldProject(
    id: id,
    name: name,
    createdAt: createdAt,
    updatedAt: time,
    tracks: value,
  );

  Map<String, Object> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
    'tracks': tracks.map((track) => track.toJson()).toList(),
  };

  factory FieldProject.fromJson(Map<String, Object?> json) => FieldProject(
    id: json['id']! as String,
    name: json['name']! as String,
    createdAt: DateTime.parse(json['createdAt']! as String),
    updatedAt: DateTime.parse(json['updatedAt']! as String),
    tracks: (json['tracks'] as List<Object?>? ?? const [])
        .map(
          (track) => GpsTrack.fromJson(
            (track! as Map<Object?, Object?>).cast<String, Object?>(),
          ),
        )
        .toList(),
  );
}

class FieldProjectState {
  const FieldProjectState({required this.projects, this.activeProjectId});

  final List<FieldProject> projects;
  final String? activeProjectId;

  static const empty = FieldProjectState(projects: []);
}

class FieldProjectStore {
  Future<void> _saveQueue = Future.value();

  Future<File> get _dataFile async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(documents.path, 'field_projects'));
    await directory.create(recursive: true);
    return File(path.join(directory.path, 'projects.json'));
  }

  Future<FieldProjectState> load() async {
    final file = await _dataFile;
    if (!await file.exists()) return FieldProjectState.empty;
    try {
      final document =
          jsonDecode(await file.readAsString()) as Map<String, Object?>;
      final projects = (document['projects'] as List<Object?>? ?? const [])
          .map(
            (project) => FieldProject.fromJson(
              (project! as Map<Object?, Object?>).cast<String, Object?>(),
            ),
          )
          .toList();
      final requestedActiveId = document['activeProjectId'] as String?;
      final activeId = projects.any((project) => project.id == requestedActiveId)
          ? requestedActiveId
          : projects.isEmpty
              ? null
              : projects.first.id;
      return FieldProjectState(projects: projects, activeProjectId: activeId);
    } catch (_) {
      return FieldProjectState.empty;
    }
  }

  Future<void> save(List<FieldProject> projects, String? activeProjectId) async {
    final encoded = jsonEncode({
      'schemaVersion': 1,
      'activeProjectId': activeProjectId,
      'projects': projects.map((project) => project.toJson()).toList(),
    });
    _saveQueue = _saveQueue.then(
      (_) => _write(encoded),
      onError: (_) => _write(encoded),
    );
    return _saveQueue;
  }

  Future<void> _write(String encoded) async {
    final file = await _dataFile;
    final temporary = File('${file.path}.saving');
    await temporary.writeAsString(encoded, flush: true);
    if (await file.exists()) await file.delete();
    await temporary.rename(file.path);
  }
}
