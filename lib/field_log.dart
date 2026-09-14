enum FieldLogKind { waypoint, text, photo }

class FieldLog {
  const FieldLog({
    required this.id,
    required this.kind,
    required this.latitude,
    required this.longitude,
    required this.title,
    required this.createdAt,
    this.notes = '',
    this.photoPath,
  });

  final String id;
  final FieldLogKind kind;
  final double latitude;
  final double longitude;
  final String title;
  final String notes;
  final DateTime createdAt;
  // Relative to the project store, never the temporary camera/gallery path.
  final String? photoPath;

  FieldLog withPhoto(String path) => FieldLog(
    id: id,
    kind: kind,
    latitude: latitude,
    longitude: longitude,
    title: title,
    notes: notes,
    createdAt: createdAt,
    photoPath: path,
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'kind': kind.name,
    'latitude': latitude,
    'longitude': longitude,
    'title': title,
    'notes': notes,
    'createdAt': createdAt.toUtc().toIso8601String(),
    'photoPath': photoPath,
  };

  factory FieldLog.fromJson(Map<String, Object?> json) => FieldLog(
    id: json['id']! as String,
    kind: FieldLogKind.values.byName(json['kind']! as String),
    latitude: (json['latitude']! as num).toDouble(),
    longitude: (json['longitude']! as num).toDouble(),
    title: json['title']! as String,
    notes: json['notes'] as String? ?? '',
    createdAt: DateTime.parse(json['createdAt']! as String),
    photoPath: json['photoPath'] as String?,
  );
}

// Persist before launching Android's camera/gallery. If Android restarts the app,
// the recovered photo still belongs to the original project and tapped location.
class PendingPhotoLog {
  const PendingPhotoLog({required this.projectId, required this.log});
  final String projectId;
  final FieldLog log;

  Map<String, Object?> toJson() => {
    'projectId': projectId,
    'log': log.toJson(),
  };

  factory PendingPhotoLog.fromJson(Map<String, Object?> json) =>
      PendingPhotoLog(
        projectId: json['projectId']! as String,
        log: FieldLog.fromJson((json['log']! as Map).cast<String, Object?>()),
      );
}
