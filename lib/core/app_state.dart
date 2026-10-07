import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'database.dart';
import 'device_store.dart';
import 'fake_sync_engine.dart';
import 'item_repository.dart';
import 'models.dart';
import 'settings_store.dart';
import 'sync_engine.dart';

class AppState extends ChangeNotifier {
  ItemRepository repository;
  DeviceStore devices;
  ItemRepository? _originalRepository;
  DeviceStore? _originalDevices;
  final SettingsStore settings;
  final Directory supportDirectory;
  SyncEngine _engine;
  SyncEngine? _originalEngine;
  SyncEngine get engine => _engine;
  bool get isDemoMode => _originalEngine != null;
  AppState({
    required this.repository,
    required this.devices,
    required this.settings,
    required SyncEngine engine,
    required this.supportDirectory,
  }) : _engine = engine {
    for (final source in [repository, devices, settings, engine]) {
      source.addListener(notifyListeners);
    }
  }
  Future<DotItem> _save(DotItem item) async {
    final saved = await repository.upsertLocal(
      item,
      hasPeer: devices.hasPeer || isDemoMode,
    );
    await engine.syncNow();
    return saved;
  }

  DotItem _item(ItemType type, String title, String body) {
    final now = DateTime.now();
    return DotItem(
      id: newId(),
      type: type,
      title: title,
      body: body,
      originDeviceId: engine.localDeviceId,
      originName: engine.localName,
      createdAt: now,
      updatedAt: now,
      etag: newId(),
    );
  }

  Future<DotItem> addText(String text) =>
      _save(_item(ItemType.text, text.trim().split('\n').first, text));
  Future<DotItem> addLink(String url) {
    final input = url.trim();
    final uri = Uri.parse(input.contains('://') ? input : 'https://$input');
    if (!['http', 'https'].contains(uri.scheme) || uri.host.isEmpty) {
      throw const FormatException('Voer een geldige link in.');
    }
    return _save(_item(ItemType.link, uri.host, uri.toString()));
  }

  Future<DotItem> addNote(String title, [String body = '']) =>
      _save(_item(ItemType.note, title, body));
  Future<void> updateNote(String id, String body, {String? title}) async {
    final item = await repository.get(id);
    if (item == null || item.deleted || item.type != ItemType.note) return;
    await _save(item.copyWith(body: body, title: title));
  }

  Future<DotItem> addFile(String path) async {
    final source = File(path);
    final item = _item(ItemType.file, p.basename(path), '');
    final directory = Directory(
      p.join(supportDirectory.path, isDemoMode ? 'demo_files' : 'files'),
    );
    await directory.create(recursive: true);
    final target = await source.copy(
      p.join(directory.path, '${item.id}_${p.basename(path)}'),
    );
    try {
      final digest = await sha256.bind(target.openRead()).first;
      return await _save(
        item.copyWith(
          fileName: p.basename(path),
          fileSize: await target.length(),
          mimeType: lookupMimeType(path) ?? 'application/octet-stream',
          sha256: digest.toString(),
          localPath: target.path,
        ),
      );
    } catch (_) {
      await target.delete();
      rethrow;
    }
  }

  Future<DotItem?> pasteAndSend() async {
    final text = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    if (text == null || text.trim().isEmpty) return null;
    return RegExp(r'^https?://', caseSensitive: false).hasMatch(text.trim())
        ? addLink(text)
        : addText(text);
  }

  Future<void> togglePin(String id) async {
    await repository.togglePin(id, hasPeer: devices.hasPeer || isDemoMode);
    await engine.syncNow();
  }

  Future<void> deleteItem(String id) async {
    await repository.delete(id, hasPeer: devices.hasPeer || isDemoMode);
    await engine.syncNow();
  }

  Future<void> copyItem(String id) async {
    final item = await repository.get(id);
    if (item == null || item.deleted) return;
    await Clipboard.setData(
      ClipboardData(
        text: item.type == ItemType.file ? item.localPath ?? '' : item.body,
      ),
    );
  }

  Future<void> clearHistory() async {
    await repository.clearHistory(hasPeer: devices.hasPeer || isDemoMode);
    await engine.syncNow();
  }

  Future<void> enterDemoMode() async {
    if (isDemoMode) return;
    final db = await DotDatabase.open(path: inMemoryDatabasePath);
    await engine.stop();
    _originalEngine = engine;
    _originalRepository = repository;
    _originalDevices = devices;
    engine.removeListener(notifyListeners);
    repository.removeListener(notifyListeners);
    devices.removeListener(notifyListeners);
    repository = ItemRepository(db);
    devices = DeviceStore(db);
    repository.addListener(notifyListeners);
    devices.addListener(notifyListeners);
    _engine = FakeSyncEngine(
      repository: repository,
      devices: devices,
      localDeviceId: _originalEngine!.localDeviceId,
      localName: _originalEngine!.localName,
      isHost: _originalEngine!.isHost,
    );
    engine.addListener(notifyListeners);
    notifyListeners();
    await engine.start();
  }

  Future<void> exitDemoMode() async {
    if (!isDemoMode) return;
    await engine.stop();
    engine.removeListener(notifyListeners);
    engine.dispose();
    repository.removeListener(notifyListeners);
    devices.removeListener(notifyListeners);
    await repository.db.close();
    repository.dispose();
    devices.dispose();
    repository = _originalRepository!;
    devices = _originalDevices!;
    _originalRepository = null;
    _originalDevices = null;
    repository.addListener(notifyListeners);
    devices.addListener(notifyListeners);
    _engine = _originalEngine!;
    _originalEngine = null;
    engine.addListener(notifyListeners);
    notifyListeners();
    await engine.start();
  }

  @override
  void dispose() {
    for (final source in [repository, devices, settings, engine]) {
      source.removeListener(notifyListeners);
    }
    engine.dispose();
    _originalEngine?.dispose();
    repository.dispose();
    devices.dispose();
    settings.dispose();
    repository.db.close();
    _originalRepository?.db.close();
    _originalRepository?.dispose();
    _originalDevices?.dispose();
    super.dispose();
  }
}
