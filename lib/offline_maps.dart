import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_map_mbtiles/flutter_map_mbtiles.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const mapCatalogUrl =
    'https://pub-1d17b2dbfd3a4bbd9f02ac50c4a6775a.r2.dev/catalog.json';

class InstalledMap {
  const InstalledMap({
    required this.id,
    required this.name,
    required this.filePath,
    required this.attribution,
    this.catalogId,
  });

  final String id;
  final String name;
  final String filePath;
  final String attribution;
  final String? catalogId;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'filePath': filePath,
    'attribution': attribution,
    'catalogId': catalogId,
  };

  factory InstalledMap.fromJson(Map<String, Object?> json) {
    return InstalledMap(
      id: json['id']! as String,
      name: json['name']! as String,
      filePath: json['filePath']! as String,
      attribution:
          json['attribution'] as String? ?? 'Offline map',
      catalogId: json['catalogId'] as String?,
    );
  }
}

class CatalogMap {
  const CatalogMap({
    required this.id,
    required this.name,
    required this.description,
    required this.downloadUri,
    required this.fileName,
    required this.sizeBytes,
    required this.attribution,
  });

  final String id;
  final String name;
  final String description;
  final Uri downloadUri;
  final String fileName;
  final int sizeBytes;
  final String attribution;

  factory CatalogMap.fromJson(Map<String, Object?> json, Uri catalogUri) {
    final file = json['file']! as String;
    final fileName = path.basename(Uri.parse(file).path);
    if (!fileName.toLowerCase().endsWith('.mbtiles')) {
      throw const FormatException('Only MBTiles catalogue files are supported');
    }
    final downloadUri = catalogUri.resolve(file);
    if (downloadUri.scheme != 'https') {
      throw const FormatException('Catalogue downloads must use HTTPS');
    }

    return CatalogMap(
      id: json['id']! as String,
      name: json['name']! as String,
      description: json['description'] as String? ?? '',
      downloadUri: downloadUri,
      fileName: fileName,
      sizeBytes: (json['sizeBytes'] as num?)?.toInt() ?? 0,
      attribution:
          json['attribution'] as String? ?? '© OpenStreetMap contributors',
    );
  }
}

class OfflineMapStore {
  static const _mapsKey = 'installed_maps_v2';
  static const _activeKey = 'active_map_id_v2';
  static const _oldPathKey = 'offline_map_path';
  static const _oldNameKey = 'offline_map_name';
  static const _oldSelectedKey = 'offline_map_selected';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  HttpClient? _downloadClient;

  Future<List<InstalledMap>> load() async {
    final encoded = await _preferences.getString(_mapsKey);
    var maps = <InstalledMap>[];
    if (encoded != null) {
      try {
        maps = (jsonDecode(encoded) as List<Object?>)
            .map(
              (item) => InstalledMap.fromJson(
                (item! as Map<Object?, Object?>).cast<String, Object?>(),
              ),
            )
            .toList();
      } catch (_) {
        maps = [];
      }
    }

    if (maps.isEmpty) {
      final oldPath = await _preferences.getString(_oldPathKey);
      if (oldPath != null && await File(oldPath).exists()) {
        maps.add(
          InstalledMap(
            id: 'import-${DateTime.now().millisecondsSinceEpoch}',
            name:
                await _preferences.getString(_oldNameKey) ?? path.basename(oldPath),
            filePath: oldPath,
            attribution: 'Imported MBTiles',
          ),
        );
        if (await _preferences.getBool(_oldSelectedKey) ?? false) {
          await setActiveId(maps.first.id);
        }
      }
    }

    maps = [
      for (final map in maps)
        if (await File(map.filePath).exists()) map,
    ];
    await _save(maps);
    return maps;
  }

  Future<String?> getActiveId() => _preferences.getString(_activeKey);

  Future<void> setActiveId(String? value) async {
    if (value == null) {
      await _preferences.remove(_activeKey);
    } else {
      await _preferences.setString(_activeKey, value);
    }
  }

  Future<InstalledMap?> importFromPhone(List<InstalledMap> current) async {
    final selected = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: const ['mbtiles'],
    );
    if (selected == null) return null;

    final destination = await _uniqueDestination(selected.name);
    final temporary = File('${destination.path}.importing');
    try {
      final output = temporary.openWrite();
      await output.addStream(selected.readAsByteStream());
      await output.close();
      _validate(temporary.path);
      await temporary.rename(destination.path);

      final installed = InstalledMap(
        id: 'import-${DateTime.now().millisecondsSinceEpoch}',
        name: selected.name,
        filePath: destination.path,
        attribution: 'Imported MBTiles',
      );
      await _save([...current, installed]);
      return installed;
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  Future<List<CatalogMap>> fetchCatalog() async {
    final catalogUri = Uri.parse(mapCatalogUrl);
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(catalogUri);
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close();
      if (response.statusCode == HttpStatus.notFound) return [];
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Catalogue returned ${response.statusCode}');
      }
      final body = await utf8.decoder.bind(response).join();
      final document = jsonDecode(body) as Map<String, Object?>;
      return (document['maps'] as List<Object?>? ?? const [])
          .map(
            (item) => CatalogMap.fromJson(
              (item! as Map<Object?, Object?>).cast<String, Object?>(),
              catalogUri,
            ),
          )
          .toList();
    } finally {
      client.close(force: true);
    }
  }

  Future<InstalledMap> download(
    CatalogMap map,
    List<InstalledMap> current,
    void Function(double?) onProgress,
  ) async {
    final destination = await _uniqueDestination(map.fileName);
    final temporary = File('${destination.path}.downloading');
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 20);
    _downloadClient = client;
    IOSink? output;
    try {
      final request = await client.getUrl(map.downloadUri);
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('Download returned ${response.statusCode}');
      }

      final expected = response.contentLength > 0
          ? response.contentLength
          : map.sizeBytes;
      var received = 0;
      output = temporary.openWrite();
      await for (final chunk in response) {
        output.add(chunk);
        received += chunk.length;
        onProgress(expected > 0 ? received / expected : null);
      }
      await output.flush();
      await output.close();
      output = null;
      _validate(temporary.path);
      await temporary.rename(destination.path);

      final installed = InstalledMap(
        id: 'library-${map.id}',
        catalogId: map.id,
        name: map.name,
        filePath: destination.path,
        attribution: map.attribution,
      );
      final updated = [
        for (final existing in current)
          if (existing.catalogId != map.id) existing,
        installed,
      ];
      await _save(updated);
      return installed;
    } finally {
      await output?.close();
      client.close(force: true);
      if (identical(_downloadClient, client)) _downloadClient = null;
      if (await temporary.exists()) await temporary.delete();
    }
  }

  void cancelDownload() {
    _downloadClient?.close(force: true);
    _downloadClient = null;
  }

  Future<void> remove(InstalledMap map, List<InstalledMap> current) async {
    await _save(current.where((item) => item.id != map.id).toList());
    final file = File(map.filePath);
    if (await file.exists()) await file.delete();
  }

  Future<File> _uniqueDestination(String originalName) async {
    final documents = await getApplicationDocumentsDirectory();
    final directory = Directory(path.join(documents.path, 'offline_maps'));
    await directory.create(recursive: true);
    final safeName = originalName.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
    final extension = path.extension(safeName);
    final stem = path.basenameWithoutExtension(safeName);
    var destination = File(path.join(directory.path, safeName));
    var suffix = 2;
    while (await destination.exists()) {
      destination = File(path.join(directory.path, '$stem-$suffix$extension'));
      suffix++;
    }
    return destination;
  }

  void _validate(String filePath) {
    final provider = MbTilesTileProvider.fromPath(path: filePath);
    try {
      provider.mbtiles.getMetadata();
    } finally {
      provider.dispose();
    }
  }

  Future<void> _save(List<InstalledMap> maps) {
    return _preferences.setString(
      _mapsKey,
      jsonEncode(maps.map((map) => map.toJson()).toList()),
    );
  }
}

String formatMapSize(int bytes) {
  if (bytes <= 0) return 'Size unavailable';
  const megabyte = 1024 * 1024;
  const gigabyte = 1024 * megabyte;
  if (bytes >= gigabyte) return '${(bytes / gigabyte).toStringAsFixed(1)} GB';
  return '${(bytes / megabyte).round()} MB';
}
