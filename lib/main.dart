import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'core/bootstrap.dart';
import 'sync/lan_sync_engine.dart';
import 'platform/desktop_shell.dart';
import 'platform/notifier.dart';
import 'platform/share_intake.dart';
import 'platform/mac_input.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final inputSink = Platform.isMacOS ? MacInput() : null;
  registerSyncEngineFactory(
    (context) => createLanEngine(context, inputSink: inputSink),
  );
  final state = await bootstrap();
  runApp(DotApp(state: state));
  // Optional integrations start after the UI has rendered its first frame.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    unawaited(
      initializePlatformIntegrations({
        'ShareIntake': () => ShareIntake.init(state),
        'DotNotifier': () => DotNotifier.init(state),
        'DesktopShell': () => DesktopShell.init(state),
      }),
    );
  });
}

/// Isolate failures and delays so each optional integration can start independently.
Future<void> initializePlatformIntegrations(
  Map<String, Future<void> Function()> initializers,
) async {
  await Future.wait(
    initializers.entries.map((entry) async {
      try {
        await entry.value();
      } catch (e) {
        debugPrint('DOT ${entry.key} init failed: $e');
      }
    }),
  );
}
