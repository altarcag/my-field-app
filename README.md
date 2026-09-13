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
- North reset control with a deliberate-rotation threshold
- Separate field projects with persistent GPS recording sessions
- Map-center target with live straight-line distance from GPS, in meters
- Tap the center target to add a waypoint, visible text label, or photo log
- Camera/gallery photo logs copied into permanent app storage, with Android recovery
- Tap a saved marker to view notes, coordinates, and its photo
- Export KMZ with routes, waypoints, text, and embedded photos; KML exports GPS only

## Field logging

Choose or create a project, then use **Record / Stop** for GPS route sessions.
Pan the map to position its center ring over the desired location. Tap the ring
and choose **Waypoint**, **Text**, or **Photo**. The coordinate and project are
fixed when starting the entry. Logs do not require GPS or an active recording.
The blue line and meter label show straight-line distance when GPS is available.
Tap the map or pan to dismiss the center menu.

Photo logs support the camera and gallery (JPEG, PNG, WebP). Photo files are
copied into app storage, so removing the source from the gallery does not remove
the log. If Android restarts the app while the picker is open, the pending log
retains its original project, location, and notes.

Use the download icon beside the project to export. **KMZ** contains the complete
project, including a `doc.kml` with relative photo references and embedded image
files; projects containing only logs can also be exported. **KML** contains only
the GPS sessions and needs at least one GPS point. Every route session remains a
separate geometry. Export takes a snapshot while recording can continue.
Existing route-only projects load with an empty log list.

GPS recording still depends on the app being active; this update does not add a
background location service. Android may pause recording while another app is
open or the screen is locked.

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
