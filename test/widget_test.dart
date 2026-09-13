import 'package:flutter_test/flutter_test.dart';

import 'package:my_field_atlas_android/main.dart';

void main() {
  testWidgets('Map screen loads', (WidgetTester tester) async {
    await tester.pumpWidget(const FieldApp());

    expect(find.text('Starting GPS…'), findsOneWidget);
    expect(find.text('© OpenStreetMap contributors'), findsOneWidget);
  });
}
