import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dot/core/database.dart';
import 'package:dot/core/device_store.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/models.dart';
import 'package:dot/core/settings_store.dart';
import 'package:dot/sync/client_connection.dart';
import 'package:dot/sync/discovery.dart';
import 'package:dot/sync/host_server.dart';
import 'package:dot/sync/identity.dart';
import 'package:dot/sync/lan_sync_engine.dart';
import 'package:dot/sync/tls_cert.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<void> eventually(Future<bool> Function() predicate) async {
  final deadline = DateTime.now().add(const Duration(seconds: 15));
  while (!await predicate()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Condition was not satisfied before timeout.');
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

class Fixture {
  final Database db;
  final ItemRepository repository;
  final DeviceStore devices;
  final SettingsStore settings;
  final LanSyncEngine engine;
  Fixture(this.db, this.repository, this.devices, this.settings, this.engine);
  static Future<Fixture> create(
    Directory root, {
    required bool host,
    SecretStore? secrets,
  }) async {
    final db = await DotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    final repository = ItemRepository(db);
    final devices = DeviceStore(db);
    await devices.load();
    final settings = SettingsStore(await SharedPreferences.getInstance());
    settings.autoReconnect = false;
    final engine = LanSyncEngine(
      repository: repository,
      devices: devices,
      settings: settings,
      supportDirectory: root,
      isHost: host,
      name: host ? 'MacBook' : 'Android',
      secrets: secrets ?? MemorySecretStore(),
      discovery: NoDiscovery(),
      bindAddress: '127.0.0.1',
      advertisedHost: '127.0.0.1',
      preferredPort: 0,
      receiveDirectory: () async => Directory('${root.path}/received'),
    );
    await engine.start();
    return Fixture(db, repository, devices, settings, engine);
  }

  Future<void> close() async {
    await engine.stop();
    engine.dispose();
    repository.dispose();
    devices.dispose();
    settings.dispose();
    await db.close();
  }

  DotItem item({ItemType type = ItemType.text, String body = 'Hallo'}) {
    final now = DateTime.now();
    return DotItem(
      id: newId(),
      type: type,
      title: 'Titel',
      body: body,
      originDeviceId: engine.localDeviceId,
      originName: engine.localName,
      createdAt: now,
      updatedAt: now,
      etag: newId(),
    );
  }
}

Future<void> pair(Fixture host, Fixture client, {bool manual = false}) async {
  final subscription = host.engine.events.listen((event) {
    if (event is PairRequestEvent) {
      unawaited(
        host.engine.respondToPairRequest(event.request.requestId, true),
      );
    }
  });
  try {
    final offer = await host.engine.createPairingOffer();
    final preview = await client.engine.previewPairing(
      manual
          ? '${offer.host}:${offer.port} ${offer.manualCode}'
          : offer.qrPayload,
    );
    await client.engine.confirmPairing(preview);
    await eventually(
      () async =>
          host.engine.status == ConnectionStatus.connected &&
          client.engine.status == ConnectionStatus.connected,
    );
  } finally {
    await subscription.cancel();
  }
}

class NetworkTestBinding extends AutomatedTestWidgetsFlutterBinding {
  @override
  bool get overrideHttpClient => false;
}

void main() {
  NetworkTestBinding();
  sqfliteFfiInit();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('TLS pin rejects any other fingerprint', () async {
    final certificate = await TlsCertificate.load(MemorySecretStore());
    final server = HostServer();
    final sockets = <WebSocket>[];
    await server.start(
      certificate,
      sockets.add,
      bindAddress: '127.0.0.1',
      preferredPort: 0,
    );
    try {
      await expectLater(
        ClientConnection.connect('127.0.0.1', server.port, '0' * 64),
        throwsA(anything),
      );
      final client = await ClientConnection.connect(
        '127.0.0.1',
        server.port,
        certificate.fingerprint,
      );
      await client.close();
    } finally {
      for (final socket in sockets) {
        await socket.close();
      }
      await server.stop();
    }
  });

  test('loopback pairs, syncs both directions, queues offline, keeps note conflicts, transfers 1 MB and revokes', () async {
    final root = await Directory.systemTemp.createTemp('dot-loopback-');
    final host = await Fixture.create(
      Directory('${root.path}/host'),
      host: true,
    );
    final client = await Fixture.create(
      Directory('${root.path}/client'),
      host: false,
    );
    try {
      await pair(host, client);
      expect(host.devices.primary!.publicKey, isNotEmpty);
      expect(client.devices.primary!.certFingerprint, isNotNull);
      final first = await host.repository.upsertLocal(host.item());
      final second = await client.repository.upsertLocal(
        client.item(body: 'Terug'),
      );
      await Future.wait([host.engine.syncNow(), client.engine.syncNow()]);
      await eventually(
        () async =>
            (await client.repository.get(first.id)) != null &&
            (await host.repository.get(second.id)) != null &&
            (await host.repository.pending()).isEmpty &&
            (await client.repository.pending()).isEmpty,
      );

      final note = await host.repository.upsertLocal(
        host.item(type: ItemType.note),
      );
      await host.engine.syncNow();
      await eventually(
        () async =>
            (await client.repository.get(note.id)) != null &&
            (await host.repository.pending()).isEmpty,
      );
      await client.engine.stop();
      await eventually(
        () async => host.engine.status != ConnectionStatus.connected,
      );
      await host.repository.upsertLocal(
        (await host.repository.get(note.id))!.copyWith(body: 'Mac-versie'),
      );
      await client.repository.upsertLocal(
        (await client.repository.get(note.id))!
            .copyWith(body: 'Android-versie'),
      );
      final queued = await client.repository.upsertLocal(
        client.item(body: 'Offline'),
      );
      await client.engine.syncNow();
      expect(
        (await client.repository.get(queued.id))!.syncState,
        SyncState.waiting,
      );
      await client.engine.start();
      await client.engine.reconnect();
      await eventually(
        () async =>
            (await host.repository.get(queued.id)) != null &&
            (await client.repository.pending()).isEmpty &&
            (await host.repository.pending()).isEmpty,
      );
      expect(
        (await host.repository.all()).where((i) => i.id == queued.id).length,
        1,
      );
      final notes = (await host.repository.all())
          .where((i) => i.type == ItemType.note)
          .toList();
      expect(
        notes.map((i) => i.body),
        containsAll(['Mac-versie', 'Android-versie']),
      );
      await Future.wait([host.engine.syncNow(), client.engine.syncNow()]);
      expect(
        (await host.repository.all()).where((i) => i.id == queued.id).length,
        1,
      );

      final bytes = Uint8List.fromList(
        List.generate(1024 * 1024, (i) => i % 251),
      );
      final source = File('${root.path}/source.bin');
      await source.writeAsBytes(bytes);
      final file = await host.repository.upsertLocal(
        host
            .item(type: ItemType.file)
            .copyWith(
              localPath: source.path,
              fileName: 'sample.bin',
              fileSize: bytes.length,
              sha256: sha256.convert(bytes).toString(),
            ),
      );
      await host.engine.syncNow();
      await eventually(
        () async =>
            (await host.repository.get(file.id))?.syncState ==
                SyncState.received &&
            (await client.repository.get(file.id))?.localPath != null,
      );
      final received = File((await client.repository.get(file.id))!.localPath!);
      expect(await received.length(), bytes.length);
      expect(
        (await sha256.bind(received.openRead()).first).toString(),
        sha256.convert(bytes).toString(),
      );
      expect(
        await Directory('${root.path}/client/received')
            .list()
            .where((e) => e.path.endsWith('.part'))
            .isEmpty,
        isTrue,
      );

      // Simulate revocation on the host while the client retains its old trust.
      await client.engine.stop();
      await host.devices.remove(client.engine.localDeviceId);
      await client.engine.start();
      await client.engine.reconnect();
      expect(client.engine.status, ConnectionStatus.failed);
      expect(host.devices.hasPeer, isFalse);
      expect(host.engine.status, isNot(ConnectionStatus.connected));
    } finally {
      await client.close();
      await host.close();
      await root.delete(recursive: true);
    }
  }, timeout: const Timeout(Duration(seconds: 90)));

  test('manual code authenticates the fingerprint and is consumed only after host confirmation', () async {
    final root = await Directory.systemTemp.createTemp('dot-manual-');
    final host = await Fixture.create(
      Directory('${root.path}/host'),
      host: true,
    );
    final client = await Fixture.create(
      Directory('${root.path}/client'),
      host: false,
    );
    try {
      final offer = await host.engine.createPairingOffer();
      await expectLater(
        client.engine.previewPairing('${offer.host}:${offer.port} AAAAAA'),
        throwsA(isA<StateError>()),
      );
      expect(host.engine.tokens.valid, isTrue);
      await pair(host, client, manual: true);
      expect(host.engine.tokens.valid, isFalse);
      final replayOffer = await host.engine.createPairingOffer();
      final replayPreview = await client.engine.previewPairing(
        replayOffer.qrPayload,
      );
      await host.engine.cancelPairingOffer();
      await expectLater(
        client.engine.confirmPairing(replayPreview),
        throwsA(isA<StateError>()),
      );
      await host.engine.unpair(client.engine.localDeviceId);
      await eventually(() async => !client.devices.hasPeer);
    } finally {
      await client.close();
      await host.close();
      await root.delete(recursive: true);
    }
  });
}
