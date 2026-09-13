import 'dart:io';

import 'package:flutter_map_cache/flutter_map_cache.dart';
import 'package:http_cache_file_store/http_cache_file_store.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum OnlineBasemap { street, satellite, topographic }

extension OnlineBasemapDetails on OnlineBasemap {
  String get id => switch (this) {
    OnlineBasemap.street => 'street',
    OnlineBasemap.satellite => 'satellite',
    OnlineBasemap.topographic => 'topographic',
  };

  String get label => switch (this) {
    OnlineBasemap.street => 'Map',
    OnlineBasemap.satellite => 'Satellite',
    OnlineBasemap.topographic => 'Topo',
  };

  String get urlTemplate => switch (this) {
    OnlineBasemap.street =>
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    OnlineBasemap.satellite =>
      'https://server.arcgisonline.com/ArcGIS/rest/services/'
          'World_Imagery/MapServer/tile/{z}/{y}/{x}',
    OnlineBasemap.topographic =>
      'https://tile.opentopomap.org/{z}/{x}/{y}.png',
  };

  int get maxNativeZoom => switch (this) {
    OnlineBasemap.street => 19,
    OnlineBasemap.satellite => 19,
    OnlineBasemap.topographic => 17,
  };

  String get attribution => switch (this) {
    OnlineBasemap.street => '© OpenStreetMap contributors',
    OnlineBasemap.satellite => 'Imagery © Esri and contributors',
    OnlineBasemap.topographic =>
      '© OpenTopoMap · © OpenStreetMap contributors',
  };
}

class OnlineMapCache {
  static const _selectedKey = 'online_basemap_v1';
  static const _userAgent = 'com.altarcag.my_field_atlas_android';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();
  final Map<OnlineBasemap, FileCacheStore> _stores = {};
  final Map<OnlineBasemap, Directory> _directories = {};

  Future<void> initialize() async {
    final supportDirectory = await getApplicationSupportDirectory();
    final root = Directory(
      path.join(supportDirectory.path, 'online_map_cache'),
    );
    await root.create(recursive: true);

    for (final basemap in OnlineBasemap.values) {
      final directory = Directory(path.join(root.path, basemap.id));
      await directory.create(recursive: true);
      _directories[basemap] = directory;
      _stores[basemap] = FileCacheStore(directory.path);
    }
  }

  CachedTileProvider providerFor(OnlineBasemap basemap) {
    return CachedTileProvider(
      store: _stores[basemap]!,
      headers: const {'User-Agent': _userAgent},
    );
  }

  Future<OnlineBasemap> getSelected() async {
    final id = await _preferences.getString(_selectedKey);
    return OnlineBasemap.values.firstWhere(
      (basemap) => basemap.id == id,
      orElse: () => OnlineBasemap.street,
    );
  }

  Future<void> setSelected(OnlineBasemap basemap) {
    return _preferences.setString(_selectedKey, basemap.id);
  }

  Future<Map<OnlineBasemap, int>> sizes() async {
    return {
      for (final basemap in OnlineBasemap.values)
        basemap: await _directorySize(_directories[basemap]!),
    };
  }

  Future<void> clear(OnlineBasemap basemap) async {
    await _stores[basemap]!.clean();
  }

  Future<int> _directorySize(Directory directory) async {
    var bytes = 0;
    await for (final entity in directory.list(recursive: true)) {
      if (entity is File) {
        try {
          bytes += await entity.length();
        } on FileSystemException {
          // A cache entry may expire while sizes are being calculated.
        }
      }
    }
    return bytes;
  }
}
