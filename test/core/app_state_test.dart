import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dot/core/app_state.dart';
import 'package:dot/core/database.dart';
import 'package:dot/core/device_store.dart';
import 'package:dot/core/fake_sync_engine.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/models.dart';
import 'package:dot/core/settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late AppState state;
  late Directory directory;
  setUp(() async {
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
    directory = await Directory.systemTemp.createTemp('dot-test-');
    final db = await DotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repository = ItemRepository(db);
    final devices = DeviceStore(db);
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
        sendDelay: const Duration(milliseconds: 5),
      ),
    );
  });
  tearDown(() async {
    await state.engine.stop();
    state.dispose();
    await directory.delete(recursive: true);
  });
  test('link normalization and file import metadata', () async {
    final link = await state.addLink(' example.com/path ');
    expect(link.body, 'https://example.com/path');
    expect(link.title, 'example.com');
    expect(() => state.addLink('file:///tmp/a'), throwsFormatException);
    final source = File('${directory.path}/source.txt');
    await source.writeAsString('DOT');
    final file = await state.addFile(source.path);
    expect(file.fileSize, 3);
    expect(file.sha256, sha256.convert([68, 79, 84]).toString());
    expect(file.mimeType, 'text/plain');
    expect(file.localPath, isNot(source.path));
    expect(await File(file.localPath!).readAsString(), 'DOT');
  });
  test('demo acknowledges sends and simulates incoming items', () async {
    await state.engine.start();
    final item = await state.addText('Hallo');
    expect(
      (await state.repository.get(item.id))!.syncState,
      SyncState.received,
    );
    await (state.engine as FakeSyncEngine).simulateIncoming();
    expect((await state.repository.all()).length, 2);
  });
  test('entering and exiting demo leaves original history intact', () async {
    final original = state.repository;
    await state.addNote('Echte notitie', 'Bewaren');
    await state.enterDemoMode();
    expect(state.isDemoMode, isTrue);
    expect(await state.repository.all(), isEmpty);
    await state.addText('Demo');
    await state.clearHistory();
    await state.exitDemoMode();
    expect(state.isDemoMode, isFalse);
    expect(state.repository, same(original));
    expect((await state.repository.all()).single.title, 'Echte notitie');
  });
}
