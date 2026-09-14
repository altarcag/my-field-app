import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'field_log.dart';
import 'field_projects.dart';

class FieldLogDraft {
  const FieldLogDraft(this.title, this.notes, this.source);
  final String title;
  final String notes;
  final ImageSource source;
}

class FieldLogDialog extends StatefulWidget {
  const FieldLogDialog({
    super.key,
    required this.kind,
    required this.projectName,
    required this.latitude,
    required this.longitude,
  });
  final FieldLogKind kind;
  final String projectName;
  final double latitude;
  final double longitude;

  @override
  State<FieldLogDialog> createState() => _FieldLogDialogState();
}

class _FieldLogDialogState extends State<FieldLogDialog> {
  final _form = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _notes = TextEditingController();
  ImageSource _source = ImageSource.camera;

  @override
  void dispose() {
    _title.dispose();
    _notes.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_form.currentState!.validate()) return;
    final title = _title.text.trim();
    Navigator.pop(
      context,
      FieldLogDraft(
        title.isEmpty ? 'Photo log' : title,
        _notes.text.trim(),
        _source,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.kind == FieldLogKind.photo;
    return AlertDialog(
      title: Text(switch (widget.kind) {
        FieldLogKind.waypoint => 'New waypoint',
        FieldLogKind.text => 'New text label',
        FieldLogKind.photo => 'New photo log',
      }),
      content: SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                widget.projectName,
                style: Theme.of(context).textTheme.labelLarge,
              ),
              Text(
                '${widget.latitude.toStringAsFixed(6)}, '
                '${widget.longitude.toStringAsFixed(6)}',
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _title,
                autofocus: !photo,
                maxLength: 160,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: widget.kind == FieldLogKind.text
                      ? 'Text shown on the map'
                      : photo
                      ? 'Title (optional)'
                      : 'Waypoint name',
                ),
                validator: (value) => !photo && (value?.trim().isEmpty ?? true)
                    ? 'Enter ${widget.kind == FieldLogKind.text ? 'a text label' : 'a name'}'
                    : null,
              ),
              TextFormField(
                controller: _notes,
                minLines: 2,
                maxLines: 5,
                maxLength: 10000,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                ),
              ),
              if (photo) ...[
                const SizedBox(height: 8),
                SegmentedButton<ImageSource>(
                  segments: const [
                    ButtonSegment(
                      value: ImageSource.camera,
                      icon: Icon(Icons.camera_alt_outlined),
                      label: Text('Camera'),
                    ),
                    ButtonSegment(
                      value: ImageSource.gallery,
                      icon: Icon(Icons.photo_library_outlined),
                      label: Text('Gallery'),
                    ),
                  ],
                  selected: {_source},
                  onSelectionChanged: (value) =>
                      setState(() => _source = value.single),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(photo ? 'Choose photo' : 'Save'),
        ),
      ],
    );
  }
}

class FieldLogPhoto extends StatefulWidget {
  const FieldLogPhoto({
    super.key,
    required this.store,
    required this.path,
    this.thumbnail = false,
  });
  final FieldProjectStore store;
  final String path;
  final bool thumbnail;

  @override
  State<FieldLogPhoto> createState() => _FieldLogPhotoState();
}

class _FieldLogPhotoState extends State<FieldLogPhoto> {
  late Future<File> _file;
  @override
  void initState() {
    super.initState();
    _file = widget.store.photoFile(widget.path);
  }

  @override
  void didUpdateWidget(FieldLogPhoto oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path || oldWidget.store != widget.store) {
      _file = widget.store.photoFile(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<File>(
    future: _file,
    builder: (context, snapshot) {
      if (!snapshot.hasData) return const Icon(Icons.photo_outlined);
      return Image.file(
        snapshot.data!,
        fit: widget.thumbnail ? BoxFit.cover : BoxFit.contain,
        width: widget.thumbnail ? 52 : null,
        height: widget.thumbnail ? 52 : null,
        cacheWidth: widget.thumbnail ? 160 : 1600,
        errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined),
      );
    },
  );
}

class FieldLogMarker extends StatelessWidget {
  const FieldLogMarker({
    super.key,
    required this.log,
    required this.store,
    required this.onTap,
  });
  final FieldLog log;
  final FieldProjectStore store;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${log.kind.name}: ${log.title}',
      child: GestureDetector(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (log.kind == FieldLogKind.photo && log.photoPath != null)
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.white, width: 3),
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: const [
                    BoxShadow(color: Colors.black26, blurRadius: 4),
                  ],
                ),
                clipBehavior: Clip.antiAlias,
                child: FieldLogPhoto(
                  store: store,
                  path: log.photoPath!,
                  thumbnail: true,
                ),
              )
            else if (log.kind == FieldLogKind.waypoint)
              const Icon(Icons.location_on, color: Color(0xFF9A3655), size: 32),
            Flexible(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.94),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  log.title,
                  maxLines: log.kind == FieldLogKind.text ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}


/// Owns its controller until Flutter removes the dialog from the widget tree.
class ProjectNameDialog extends StatefulWidget {
  const ProjectNameDialog({super.key});

  @override
  State<ProjectNameDialog> createState() => _ProjectNameDialogState();
}

class _ProjectNameDialogState extends State<ProjectNameDialog> {
  final _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _controller.text.trim();
    if (name.isNotEmpty) Navigator.pop(context, name);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('New field project'),
    content: TextField(
      controller: _controller,
      autofocus: true,
      textCapitalization: TextCapitalization.words,
      decoration: const InputDecoration(
        labelText: 'Project name',
        hintText: 'Cappadocia — September 2026',
      ),
      onSubmitted: (_) => _submit(),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(onPressed: _submit, child: const Text('Create')),
    ],
  );
}
