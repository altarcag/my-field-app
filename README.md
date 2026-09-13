# My Field App

An Android-first, offline-capable field mapping and GPS application built with
Flutter.

## Current features

- Live high-accuracy GPS position, altitude, and accuracy radius
- OpenStreetMap, Esri World Imagery, and OpenTopoMap layer selection
- Persistent browse cache with separate storage totals for each online layer
- Multiple offline raster MBTiles maps
- Import MBTiles through Android's file picker
- Downloadable map catalogue backed by Cloudflare R2
- Persistent map selection and on-device map deletion
- North reset control for map rotation

## Map catalogue

The app reads its catalogue from:

`https://pub-1d17b2dbfd3a4bbd9f02ac50c4a6775a.r2.dev/catalog.json`

An example manifest is available at `maps/catalog.example.json`. Map file paths
are resolved relative to `catalog.json`. Only HTTPS-hosted raster `.mbtiles`
packages are currently accepted.

The R2 bucket should use this layout:

```text
catalog.json
maps/
  central-anatolia.mbtiles
  turkey-overview.mbtiles
```

## Development

```bash
flutter pub get
flutter analyze
flutter test
flutter run
```
