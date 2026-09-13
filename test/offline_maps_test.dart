import 'package:flutter_test/flutter_test.dart';
import 'package:my_field_atlas_android/offline_maps.dart';

void main() {
  test('catalogue entries resolve files relative to catalog.json', () {
    final entry = CatalogMap.fromJson(
      {
        'id': 'central-anatolia',
        'name': 'Central Anatolia',
        'description': 'Offline field map',
        'file': 'maps/central-anatolia.mbtiles',
        'sizeBytes': 123,
        'attribution': '© OpenStreetMap contributors',
      },
      Uri.parse('https://maps.example/catalog.json'),
    );

    expect(
      entry.downloadUri.toString(),
      'https://maps.example/maps/central-anatolia.mbtiles',
    );
    expect(entry.fileName, 'central-anatolia.mbtiles');
  });

  test('catalogue rejects non-HTTPS downloads', () {
    expect(
      () => CatalogMap.fromJson(
        {
          'id': 'unsafe',
          'name': 'Unsafe',
          'file': 'http://maps.example/unsafe.mbtiles',
        },
        Uri.parse('https://maps.example/catalog.json'),
      ),
      throwsFormatException,
    );
  });
}
