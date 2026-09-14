import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_field_atlas_android/field_log_widgets.dart';

void main() {
  testWidgets('project dialog survives repeated focused create and cancel',
      (tester) async {
    String? result;
    await tester.pumpWidget(MaterialApp(
      home: Builder(builder: (context) {
        return Scaffold(
          body: TextButton(
            onPressed: () async {
              result = await showDialog<String>(
                context: context,
                builder: (_) => const ProjectNameDialog(),
              );
            },
            child: const Text('Open'),
          ),
        );
      }),
    ));
    for (var i = 0; i < 3; i++) {
      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '  Project $i  ');
      await tester.tap(find.text('Create'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.takeException(), isNull);
      await tester.pumpAndSettle();
      expect(result, 'Project $i');
      expect(tester.takeException(), isNull);
    }
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Cancelled');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(result, isNull);
    expect(tester.takeException(), isNull);
  });
}
