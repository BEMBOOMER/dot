import 'dart:io';

import 'package:dot/app.dart';
import 'package:dot/core/app_state.dart';
import 'package:dot/core/database.dart';
import 'package:dot/core/device_store.dart';
import 'package:dot/core/fake_sync_engine.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/settings_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppState state;
  late Database database;
  late Directory directory;

  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('dot-smoke-');
    database = await DotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repository = ItemRepository(database);
    final devices = DeviceStore(database);
    state = AppState(
      repository: repository,
      devices: devices,
      settings: SettingsStore(await SharedPreferences.getInstance()),
      supportDirectory: directory,
      engine: FakeSyncEngine(
        repository: repository,
        devices: devices,
        localDeviceId: 'local',
        localName: 'MacBook',
        connectionDelay: Duration.zero,
        sendDelay: Duration.zero,
      ),
    );
  });

  tearDown(() async {
    // DotApp owns and disposes AppState when the test unmounts it.
    await database.close();
    await directory.delete(recursive: true);
  });

  testWidgets('real app shows the Dutch welcome copy', (tester) async {
    await tester.binding.setSurfaceSize(const Size(700, 1200));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(DotApp(state: state));
    await tester.pumpAndSettle();
    expect(find.text('Je telefoon en MacBook, verbonden.'), findsOneWidget);
    expect(find.text('Eerst bekijken'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
