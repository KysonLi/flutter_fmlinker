// This is a basic Flutter widget test.
//
// The default counter template test was replaced with a minimal smoke test,
// since the example app is a barcode scanner demo rather than a counter app.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('Smoke test builds a basic widget tree', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: Text('mobile scanner')),
      ),
    );

    expect(find.text('mobile scanner'), findsOneWidget);
  });
}
