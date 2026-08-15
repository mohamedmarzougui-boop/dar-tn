import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile_app/main.dart';

void main() {
  testWidgets('App boots and shows the map view app bar', (WidgetTester tester) async {
    await tester.pumpWidget(const DarTnApp());
    await tester.pump();

    expect(find.text('Dar-TN | Map View'), findsOneWidget);
    expect(find.byIcon(Icons.person_outline), findsOneWidget);
  });
}
