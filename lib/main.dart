import 'package:flutter/material.dart';

import 'app.dart';
import 'core/bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  registerSyncEngineFactory(createDemoEngine);
  final state = await bootstrap();
  runApp(DotApp(state: state));
}
