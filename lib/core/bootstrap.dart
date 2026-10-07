import 'dart:io';

import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_state.dart';
import 'database.dart';
import 'device_store.dart';
import 'fake_sync_engine.dart';
import 'item_repository.dart';
import 'settings_store.dart';
import 'sync_engine.dart';

class EngineContext {
  final ItemRepository repository;
  final DeviceStore devices;
  final SettingsStore settings;
  final Directory supportDirectory;
  final String localDeviceId;
  final String localName;
  final bool isHost;
  const EngineContext({
    required this.repository,
    required this.devices,
    required this.settings,
    required this.supportDirectory,
    required this.localDeviceId,
    required this.localName,
    required this.isHost,
  });
}

typedef SyncEngineFactory = SyncEngine Function(EngineContext context);
SyncEngineFactory? _engineFactory;
void registerSyncEngineFactory(SyncEngineFactory factory) =>
    _engineFactory = factory;
SyncEngine createDemoEngine(EngineContext context) => FakeSyncEngine(
  repository: context.repository,
  devices: context.devices,
  localDeviceId: context.localDeviceId,
  localName: context.localName,
  isHost: context.isHost,
);

Future<AppState> bootstrap({SyncEngineFactory? engineFactory}) async {
  final prefs = await SharedPreferences.getInstance();
  final support = await getApplicationSupportDirectory();
  await support.create(recursive: true);
  final db = await DotDatabase.open();
  try {
    final repository = ItemRepository(db);
    final devices = DeviceStore(db);
    await devices.load();
    final settings = SettingsStore(prefs);
    var id = prefs.getString('localDeviceId');
    if (id == null) {
      id = newId();
      await prefs.setString('localDeviceId', id);
    }
    final context = EngineContext(
      repository: repository,
      devices: devices,
      settings: settings,
      supportDirectory: support,
      localDeviceId: id,
      localName:
          settings.deviceName ?? (Platform.isMacOS ? 'MacBook' : 'Android'),
      isHost: Platform.isMacOS,
    );
    final engine = (engineFactory ?? _engineFactory ?? createDemoEngine)(
      context,
    );
    final state = AppState(
      repository: repository,
      devices: devices,
      settings: settings,
      engine: engine,
      supportDirectory: support,
    );
    await engine.start();
    return state;
  } catch (_) {
    await db.close();
    rethrow;
  }
}
