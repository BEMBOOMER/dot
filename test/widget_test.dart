import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dot/ui/screens/settings_screen.dart';

void main() {
  testWidgets('placeholder screen uses Dutch copy', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingsScreen()));
    expect(find.text('Instellingen'), findsNWidgets(2));
  });
}
