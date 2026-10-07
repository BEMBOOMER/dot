import 'dart:async';

import 'package:dot/main.dart' as startup;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('platform failures do not block rendering or other inits', (
    tester,
  ) async {
    final pending = Completer<void>();
    final messages = <String>[];
    final originalDebugPrint = debugPrint;
    debugPrint = (message, {wrapWidth}) {
      if (message != null) messages.add(message);
    };
    addTearDown(() => debugPrint = originalDebugPrint);

    var notifierStarted = false;
    final initialization = startup.initializePlatformIntegrations({
      'ShareIntake': () => pending.future,
      'DesktopShell': () async => throw StateError('tray unavailable'),
      'DotNotifier': () async {
        notifierStarted = true;
      },
    });
    await tester.pumpWidget(const MaterialApp(home: Text('DOT werkt')));
    await tester.pump();
    expect(find.text('DOT werkt'), findsOneWidget);
    expect(notifierStarted, isTrue);
    expect(messages.single, contains('DOT DesktopShell init failed:'));
    expect(tester.takeException(), isNull);
    pending.complete();
    await initialization;
    debugPrint = originalDebugPrint;
  });

  test('synchronous init failures are also guarded', () async {
    await startup.initializePlatformIntegrations({
      'DesktopShell': () => throw StateError('sync failure'),
    });
  });
}
