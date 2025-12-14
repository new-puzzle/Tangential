// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package.

import 'package:flutter_test/flutter_test.dart';
import 'package:tangential/main.dart';

void main() {
  testWidgets('App should build without crashing', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const TangentialApp());

    // Verify the app title is displayed
    expect(find.text('Tangential'), findsOneWidget);
  });
}
