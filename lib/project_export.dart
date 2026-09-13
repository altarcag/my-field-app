import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

import 'field_projects.dart';

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

String projectToKml(FieldProject project) {
  final tracks = project.tracks.where((track) => track.points.isNotEmpty);
  final buffer = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="UTF-8"?>')
    ..writeln('<kml xmlns="http://www.opengis.net/kml/2.2">')
    ..writeln('  <Document>')
    ..writeln('    <name>${_xml(project.name)}</name>')
    ..writeln('    <Style id="gps-track">')
    ..writeln('      <LineStyle><color>ff55369a</color><width>4</width></LineStyle>')
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
        ..writeln(
          '          <coordinates>${_coordinate(point)}</coordinates>',
        )
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

  buffer
    ..writeln('    </Folder>')
    ..writeln('  </Document>')
    ..writeln('</kml>');
  return buffer.toString();
}

Uint8List projectToKmz(FieldProject project) {
  final archive = Archive()
    ..addFile(ArchiveFile.string('doc.kml', projectToKml(project)));
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

Uint8List projectExportBytes(
  FieldProject project,
  ProjectExportFormat format,
) {
  if (format == ProjectExportFormat.kmz) return projectToKmz(project);
  return Uint8List.fromList(utf8.encode(projectToKml(project)));
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
