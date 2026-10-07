import 'package:flutter/material.dart';

import 'app.dart';
import 'core/bootstrap.dart';
import 'sync/lan_sync_engine.dart';
import 'platform/desktop_shell.dart';
import 'platform/notifier.dart';
import 'platform/share_intake.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerSyncEngineFactory(createLanEngine);
  final state = await bootstrap();
  await ShareIntake.init(state);
  await DotNotifier.init(state);
  await DesktopShell.init(state);
  runApp(DotApp(state: state));
}
