import 'dart:async';
import 'dart:io';

import 'package:dot/core/models.dart';
import 'package:dot/core/remote_input.dart';
import 'package:dot/sync/client_connection.dart';
import 'package:dot/sync/identity.dart';
import 'package:dot/sync/input_rate_limiter.dart';
import 'package:dot/sync/input_sink.dart';
import 'package:dot/sync/protocol.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'lan_sync_engine_test.dart'
    show Fixture, pair, eventually, NetworkTestBinding;

class RecordingInputSink implements InputSink {
  @override
  final ValueNotifier<bool> trusted = ValueNotifier(true);
  final inputs = <RemoteInput>[];
  int resets = 0;
  bool failDispatch = false;
  @override
  Future<void> refreshTrust() async {}
  @override
  Future<bool> dispatch(RemoteInput input) async {
    if (failDispatch) throw StateError('Native input unavailable');
    inputs.add(input);
    return true;
  }

  @override
  Future<void> reset() async {
    resets++;
  }
}

/// A raw, pinned socket lets tests bypass client-side guards and send malicious
/// input to the host. It uses the real paired identity and challenge protocol.
class RawPeer {
  final ClientConnection connection;
  final StreamIterator<dynamic> frames;
  final receivedTypes = <String>[];
  RawPeer(this.connection) : frames = StreamIterator(connection.socket);
  Future<Map<String, dynamic>> until(String type) async {
    while (await frames.moveNext().timeout(const Duration(seconds: 5))) {
      final frame = frames.current;
      if (frame is String) {
        final message = decodeMessage(frame);
        receivedTypes.add(message['t'] as String);
        if (message['t'] == type) return message;
      }
    }
    throw StateError('Socket closed before $type');
  }

  void send(String type, [Map<String, Object?> fields = const {}]) =>
      connection.socket.add(encodeMessage(type, fields));
  Future<void> barrier() async {
    send('ping');
    await until('pong');
  }

  Future<void> close() async {
    await frames.cancel();
    await connection.close();
  }
}

void main() {
  NetworkTestBinding();
  sqfliteFfiInit();
  late Directory root;
  late Fixture host;
  late Fixture client;
  late RecordingInputSink sink;
  late MemorySecretStore clientSecrets;
  Duration clock = Duration.zero;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('dot-remote-input-');
    sink = RecordingInputSink();
    clientSecrets = MemorySecretStore();
    clock = Duration.zero;
    host = await Fixture.create(
      Directory('${root.path}/host'),
      host: true,
      inputSink: sink,
      inputClock: () => clock,
    );
    client = await Fixture.create(
      Directory('${root.path}/client'),
      host: false,
      secrets: clientSecrets,
    );
  });

  tearDown(() async {
    await client.close();
    await host.close();
    sink.trusted.dispose();
    await root.delete(recursive: true);
  });

  Future<RawPeer> rawAuthenticated({bool hello = true}) async {
    final peer = client.devices.primary!;
    final raw = RawPeer(
      await ClientConnection.connect(
        peer.host!,
        peer.port!,
        peer.certFingerprint!,
      ),
    );
    final challenge = await raw.until('challenge');
    final identity = await DeviceIdentity.load(clientSecrets);
    raw.send('auth', {
      'deviceId': identity.deviceId,
      'nonce': challenge['nonce'],
      'sig': await identity.sign('client:${challenge['nonce']}'),
      'clientNonce': randomNonce(),
    });
    await raw.until('hello');
    if (hello) {
      raw.send('hello', {
        'deviceId': identity.deviceId,
        'proto': protocolVersion,
      });
      await raw.until('input_status');
    }
    return raw;
  }

  test(
    'paired sendInput executes in order without items or an outbox',
    () async {
      client.engine.sendInput(const RemoteInput.key(RemoteKey.next));
      expect(sink.inputs, isEmpty);
      await pair(host, client);
      await eventually(() async => client.engine.remoteStatus.value.available);
      expect(
        client.engine.remoteStatus.value,
        const RemoteInputStatus(enabled: true, trusted: true, available: true),
      );
      final inputs = <RemoteInput>[
        const RemoteInput.move(1.25, -3),
        const RemoteInput.click(RemoteButton.left, count: 2),
        const RemoteInput.click(RemoteButton.right),
        const RemoteInput.drag(down: true),
        const RemoteInput.move(4, 5),
        const RemoteInput.drag(down: false),
        const RemoteInput.scroll(-1, 10),
        for (final key in RemoteKey.values) RemoteInput.key(key),
        for (final media in RemoteMedia.values) RemoteInput.media(media),
      ];
      for (final input in inputs) {
        client.engine.sendInput(input);
      }
      await eventually(() async => sink.inputs.length == inputs.length);
      expect(sink.inputs.map((i) => i.toWire()), inputs.map((i) => i.toWire()));
      expect(await host.repository.all(), isEmpty);
      expect(await client.repository.pending(), isEmpty);
      expect(host.engine.status, ConnectionStatus.connected);
      host.engine.sendInput(const RemoteInput.key(RemoteKey.next));
      expect(sink.inputs.length, inputs.length);
      await client.engine.stop();
      expect(client.engine.remoteStatus.value, const RemoteInputStatus());
      await eventually(
        () async => host.engine.status != ConnectionStatus.connected,
      );
      expect(sink.resets, greaterThan(0));
    },
  );

  test(
    'unauthenticated and pending pairing sockets cannot execute input',
    () async {
      final offer = await host.engine.createPairingOffer();
      final preview = await client.engine.previewPairing(offer.qrPayload);
      final raw = RawPeer(
        await ClientConnection.connect(
          offer.host,
          offer.port,
          preview.certFingerprint!,
        ),
      );
      try {
        final challenge = await raw.until('challenge');
        raw.send('input', const RemoteInput.key(RemoteKey.next).toWire());
        final identity = await DeviceIdentity.load(clientSecrets);
        final request = host.engine.events
            .where((event) => event is PairRequestEvent)
            .first;
        raw.send('pair', {
          'requestId': 'unapproved',
          'token': preview.token,
          'deviceId': identity.deviceId,
          'name': 'Android',
          'platform': 'android',
          'pubKey': identity.publicKey,
          'nonce': challenge['nonce'],
          'sig': await identity.sign('client:${challenge['nonce']}'),
          'clientNonce': randomNonce(),
        });
        await request.timeout(const Duration(seconds: 5));
        raw.send('input', const RemoteInput.drag(down: true).toWire());
        raw.send('input', const RemoteInput.move(20, 30).toWire());
        await host.engine.respondToPairRequest('unapproved', false);
        await raw.until('pair_result');
        expect(sink.inputs, isEmpty);
        expect(host.devices.hasPeer, isFalse);
      } finally {
        await raw.close();
      }
    },
  );

  test(
    'authenticated input before hello and after revocation is ignored',
    () async {
      await pair(host, client);
      final raw = await rawAuthenticated(hello: false);
      try {
        raw.send('input', const RemoteInput.key(RemoteKey.next).toWire());
        await raw.barrier();
        expect(sink.inputs, isEmpty);
        raw.send('hello', {
          'deviceId': client.engine.localDeviceId,
          'proto': protocolVersion,
        });
        await raw.until('input_status');
        raw.send('input', const RemoteInput.key(RemoteKey.space).toWire());
        await raw.barrier();
        expect(sink.inputs.length, 1);
        await host.devices.remove(client.engine.localDeviceId);
        raw.send('input', const RemoteInput.key(RemoteKey.next).toWire());
        raw.send('hello', {
          'deviceId': client.engine.localDeviceId,
          'proto': protocolVersion,
        });
        await eventually(
          () async => host.engine.status != ConnectionStatus.connected,
        );
        expect(sink.inputs.length, 1);
      } finally {
        await raw.close();
      }
    },
  );

  test('disabled setting and revoked native trust block raw input and publish status', () async {
    await pair(host, client);
    await eventually(() async => client.engine.remoteStatus.value.available);
    host.settings.remoteControl = false;
    await eventually(() async => !client.engine.remoteStatus.value.enabled);
    host.settings.remoteControl = true;
    await eventually(() async => client.engine.remoteStatus.value.enabled);
    sink.trusted.value = false;
    await eventually(() async => !client.engine.remoteStatus.value.trusted);
    sink.trusted.value = true;
    await eventually(() async => client.engine.remoteStatus.value.trusted);
    final raw = await rawAuthenticated();
    try {
      host.settings.remoteControl = false;
      raw.send('input', const RemoteInput.key(RemoteKey.next).toWire());
      await raw.barrier();
      expect(sink.inputs, isEmpty);
      host.settings.remoteControl = true;
      sink.trusted.value = false;
      raw.send('input', const RemoteInput.key(RemoteKey.next).toWire());
      await raw.barrier();
      expect(sink.inputs, isEmpty);
      sink.trusted.value = true;
      raw.send('input', const RemoteInput.key(RemoteKey.prev).toWire());
      await raw.barrier();
      expect(sink.inputs.single.toWire()['key'], 'prev');
      expect(sink.resets, greaterThan(0));
    } finally {
      await raw.close();
    }
  });

  test(
    'rate limit drops excess on arrival and recovers after one second',
    () async {
      await pair(host, client);
      final raw = await rawAuthenticated();
      try {
        for (var i = 0; i < 400; i++) {
          raw.send('input', const RemoteInput.move(1, 2).toWire());
        }
        await raw.barrier();
        expect(sink.inputs.length, InputRateLimiter.limit);
        clock = const Duration(microseconds: 999999);
        raw.send('input', const RemoteInput.move(1, 2).toWire());
        await raw.barrier();
        expect(sink.inputs.length, 240);
        clock = const Duration(seconds: 1);
        raw.send('input', const RemoteInput.move(1, 2).toWire());
        await raw.barrier();
        expect(sink.inputs.length, 241);
        expect(host.engine.status, ConnectionStatus.connected);
      } finally {
        await raw.close();
      }
    },
  );

  test(
    'invalid and unknown inputs drop without acknowledgments or sync failure',
    () async {
      await pair(host, client);
      final raw = await rawAuthenticated();
      try {
        for (final wire in [
          {'k': 'move', 'dx': 3000, 'dy': 0},
          {'k': 'scroll', 'dx': '2', 'dy': 0},
          {'k': 'click', 'b': 'middle', 'n': 1},
          {'k': 'key', 'key': 'launch'},
          {'k': 'unknown'},
        ]) {
          raw.send('input', wire);
        }
        raw.send('input', const RemoteInput.key(RemoteKey.next).toWire());
        await raw.barrier();
        expect(sink.inputs.length, 1);
        expect(host.engine.status, ConnectionStatus.connected);
        sink.failDispatch = true;
        raw.send('input', const RemoteInput.key(RemoteKey.next).toWire());
        await raw.barrier();
        expect(host.engine.status, ConnectionStatus.connected);
        expect(await host.repository.all(), isEmpty);
        expect(raw.receivedTypes, isNot(contains('ack')));
        expect(raw.receivedTypes, isNot(contains('file_ack')));
      } finally {
        await raw.close();
      }
    },
  );

  test('sliding rate window does not double-burst at a fixed boundary', () {
    var now = const Duration(milliseconds: 999);
    final limiter = InputRateLimiter(clock: () => now);
    for (var i = 0; i < 240; i++) {
      expect(limiter.allow(), isTrue);
    }
    now = const Duration(seconds: 1);
    expect(limiter.allow(), isFalse);
    now = const Duration(milliseconds: 1999);
    expect(limiter.allow(), isTrue);
  });
}
