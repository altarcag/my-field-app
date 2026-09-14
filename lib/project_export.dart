import 'dart:convert';
import 'dart:typed_data';
import 'dart:isolate';

import 'package:archive/archive.dart';

import 'field_projects.dart';
import 'field_log.dart';

enum ProjectExportFormat { kml, kmz }

String projectFileName(FieldProject project, ProjectExportFormat format) {
  final safeName = project.name
      .trim()
      .toLowerCase()
      .replaceAll(RegExp(r'[\\/:*?"<>|&]+'), '-')
      .replaceAll(RegExp(r'\s+'), '-')
      .replaceAll(RegExp(r'-+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  final baseName = safeName.isEmpty ? 'field-project' : safeName;
  return '$baseName.${format.name}';
}

String projectToKml(FieldProject project, {bool includeLogs = false}) {
  final tracks = project.tracks.where((track) => track.points.isNotEmpty);
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
    ..writeln('  <Document>')
    ..writeln('    <name>${_xml(project.name)}</name>')
    ..writeln('    <Style id="gps-track">')
    ..writeln(
      '      <LineStyle><color>ff55369a</color><width>4</width></LineStyle>',
    )
    ..writeln('    </Style>')
    ..writeln('    <Style id="gps-point">')
    ..writeln('      <IconStyle><scale>0.8</scale></IconStyle>')
    ..writeln('    </Style>')
    ..writeln('    <Folder>')
    ..writeln('      <name>GPS tracks</name>');

  var index = 0;
  for (final track in tracks) {
    index += 1;
    final name = 'GPS track $index';
    buffer
      ..writeln('      <Placemark>')
      ..writeln('        <name>$name</name>')
      ..writeln('        <ExtendedData>')
      ..writeln(
        '          <Data name="startedAt"><value>${track.startedAt.toUtc().toIso8601String()}</value></Data>',
      );
    if (track.endedAt != null) {
      buffer.writeln(
        '          <Data name="endedAt"><value>${track.endedAt!.toUtc().toIso8601String()}</value></Data>',
      );
    }
    buffer.writeln('        </ExtendedData>');

    if (track.points.length == 1) {
      final point = track.points.single;
      buffer
        ..writeln('        <styleUrl>#gps-point</styleUrl>')
        ..writeln('        <Point>')
        ..writeln('          <altitudeMode>absolute</altitudeMode>')
        ..writeln('          <coordinates>${_coordinate(point)}</coordinates>')
        ..writeln('        </Point>');
    } else {
      buffer
        ..writeln('        <styleUrl>#gps-track</styleUrl>')
        ..writeln('        <LineString>')
        ..writeln('          <tessellate>1</tessellate>')
        ..writeln('          <altitudeMode>absolute</altitudeMode>')
        ..writeln('          <coordinates>');
      for (final point in track.points) {
        buffer.writeln('            ${_coordinate(point)}');
      }
      buffer
        ..writeln('          </coordinates>')
        ..writeln('        </LineString>');
    }
    buffer.writeln('      </Placemark>');
  }

  buffer.writeln('    </Folder>');
  if (includeLogs) {
    buffer
      ..writeln(
        '<Style id="field-text"><IconStyle><scale>0</scale></IconStyle>'
        '<LabelStyle><color>ff2e4235</color><scale>1.1</scale></LabelStyle></Style>',
      )
      ..writeln('<Folder><name>Field logs</name>');
    for (final log in project.logs) {
      final photo = log.photoPath == null ? null : _photoArchivePath(log);
      final html = StringBuffer(
        '<p>${_xml(log.notes).replaceAll('\n', '<br/>')}</p>',
      );
      if (photo != null) {
        html.write('<img src="$photo" width="1200" alt="${_xml(log.title)}"/>');
      }
      buffer
        ..writeln('<Placemark>')
        ..writeln('<name>${_xml(log.title)}</name>')
        ..writeln('<description>${_xml(html.toString())}</description>')
        ..writeln(
          '<TimeStamp><when>${log.createdAt.toUtc().toIso8601String()}</when></TimeStamp>',
        );
      if (log.kind == FieldLogKind.text) {
        buffer.writeln('<styleUrl>#field-text</styleUrl>');
      }
      buffer
        ..writeln(
          '<ExtendedData><Data name="kind"><value>${log.kind.name}</value></Data>'
          '<Data name="logId"><value>${_xml(log.id)}</value></Data></ExtendedData>',
        )
        ..writeln(
          '<Point><altitudeMode>clampToGround</altitudeMode><coordinates>'
          '${log.longitude.toStringAsFixed(8)},${log.latitude.toStringAsFixed(8)}'
          '</coordinates></Point>',
        )
        ..writeln('</Placemark>');
    }
    buffer.writeln('</Folder>');
  }
  buffer
    ..writeln('  </Document>')
    ..writeln('</kml>');
  return buffer.toString();
}

String _photoArchivePath(FieldLog log) {
  // Use a safe archive name independent of the phone's absolute storage path.
  final name = log.photoPath!.replaceAll('\\', '/').split('/').last;
  return 'photos/${Uri.encodeComponent(log.id)}-${Uri.encodeComponent(name)}';
}

Uint8List projectToKmz(
  FieldProject project, {
  Map<String, Uint8List> photos = const {},
}) {
  final archive = Archive()
    ..addFile(
      ArchiveFile.string('doc.kml', projectToKml(project, includeLogs: true)),
    );
  final added = <String>{};
  for (final log in project.logs) {
    if (log.kind == FieldLogKind.photo && log.photoPath == null) {
      throw StateError('Photo missing for "${log.title}".');
    }
    if (log.photoPath == null) continue;
    final bytes = photos[log.photoPath];
    if (bytes == null || bytes.isEmpty) {
      throw StateError('Photo missing for "${log.title}". Export cancelled.');
    }
    final name = _photoArchivePath(log);
    if (added.add(name))
      archive.addFile(ArchiveFile(name, bytes.length, bytes));
  }
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Future<Uint8List> projectExportBytes(
  FieldProject project,
  ProjectExportFormat format, {
  FieldProjectStore? store,
}) async {
  if (format == ProjectExportFormat.kml) {
    return Uint8List.fromList(utf8.encode(projectToKml(project)));
  }
  final photos = <String, Uint8List>{};
  final photoStore = store ?? FieldProjectStore();
  for (final log in project.logs) {
    final path = log.photoPath;
    if (path != null && !photos.containsKey(path)) {
      final file = await photoStore.photoFile(path);
      if (!await file.exists()) {
        throw StateError('Photo missing for "${log.title}". Export cancelled.');
      }
      photos[path] = await file.readAsBytes();
    }
  }
  // Keep ZIP compression off the UI isolate while GPS updates continue.
  return Isolate.run(() => projectToKmz(project, photos: photos));
}

String _coordinate(TrackPoint point) =>
    '${point.longitude.toStringAsFixed(8)},'
    '${point.latitude.toStringAsFixed(8)},'
    '${point.altitude.toStringAsFixed(2)}';

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
