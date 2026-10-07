import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/bootstrap.dart';
import '../core/device_store.dart';
import '../core/item_repository.dart';
import '../core/models.dart';
import '../core/settings_store.dart';
import '../core/sync_engine.dart';
import 'client_connection.dart';
import 'discovery.dart';
import 'file_transfer.dart';
import 'host_server.dart';
import 'identity.dart';
import 'protocol.dart';
import 'tls_cert.dart';

SyncEngine createLanEngine(EngineContext context) => LanSyncEngine(
  repository: context.repository,
  devices: context.devices,
  settings: context.settings,
  supportDirectory: context.supportDirectory,
  initialDeviceId: context.localDeviceId,
  name: context.localName,
  isHost: context.isHost,
);

class _Session {
  final WebSocket socket;
  final ClientConnection? client;
  final PairingPreview? preview;
  final Completer<PairedDevice> ready = Completer();
  final String challenge = randomNonce();
  final String clientNonce = randomNonce();
  final String requestId = newId();
  final DateTime createdAt = DateTime.now();
  DateTime lastSeen = DateTime.now();
  Future<void> queue = Future.value();
  PairedDevice? peer;
  bool authenticated = false;
  bool hello = false;
  bool closed = false;
  Timer? deadline;
  Timer? heartbeat;
  _Session(this.socket, {this.client, this.preview}) {
    // Some host-side sessions never have a waiter.
    ready.future.then<void>((_) {}, onError: (Object _, StackTrace _) {});
  }
  void send(String type, [Map<String, Object?> fields = const {}]) {
    if (!closed) socket.add(encodeMessage(type, fields));
  }
}

class _PairRequest {
  final _Session session;
  final PairedDevice device;
  final String token;
  _PairRequest(this.session, this.device, this.token);
}

class LanSyncEngine extends SyncEngine {
  final ItemRepository repository;
  final DeviceStore devices;
  final SettingsStore settings;
  final Directory supportDirectory;
  final String? initialDeviceId;
  final String name;
  @override
  final bool isHost;
  final LanDiscovery discovery;
  final SecretStore secrets;
  final String bindAddress;
  final String? advertisedHost;
  final int preferredPort;
  final Future<Directory> Function()? receiveDirectory;
  final Future<bool> Function()? networkAvailable;
  final HostServer _server = HostServer();
  final PairingTokens tokens = PairingTokens();
  final StreamController<SyncEvent> _events = StreamController.broadcast();
  final Map<String, HostAddress> _hosts = {};
  final Set<_Session> _sessions = {};
  final Map<String, _PairRequest> _requests = {};
  final Map<String, String> _inFlight = {};
  late final FileTransfer _files;
  DeviceIdentity? _identity;
  TlsCertificate? _certificate;
  _Session? _active;
  ConnectionStatus _status = ConnectionStatus.unpaired;
  String? _lastError;
  String? _peerName;
  bool _running = false;
  bool _transportReady = false;
  bool _activeApp = true;
  bool _connecting = false;
  bool _flushing = false;
  bool _flushAgain = false;
  bool _disposed = false;
  Timer? _reconnectTimer;
  Timer? _offerTimer;
  int _backoff = 1;
  int _generation = 0;

  LanSyncEngine({
    required this.repository,
    required this.devices,
    required this.settings,
    required this.supportDirectory,
    required this.isHost,
    this.initialDeviceId,
    this.name = 'DOT',
    LanDiscovery? discovery,
    SecretStore? secrets,
    this.bindAddress = '0.0.0.0',
    this.advertisedHost,
    this.preferredPort = 48620,
    this.receiveDirectory,
    this.networkAvailable,
  }) : discovery = discovery ?? BonjourDiscovery(),
       secrets = secrets ?? SecureSecretStore(supportDirectory) {
    _files = FileTransfer(
      repository: repository,
      downloadDirectory: _downloadDirectory,
      send: (type, fields) => _active?.send(type, fields),
      sendBinary: (bytes) {
        _active?.socket.add(bytes);
      },
      onSent: (id) {
        _inFlight.remove(id);
        _emit(ItemSentEvent(id));
      },
      onReceived: (id) => _emit(ItemReceivedEvent(id)),
      onFinished: (id) {
        _inFlight.remove(id);
        if (_running) _background(syncNow());
      },
    );
    repository.addListener(_repositoryChanged);
    settings.addListener(_settingsChanged);
  }

  @override
  ConnectionStatus get status => _status;
  @override
  String? get peerName => _peerName ?? devices.primary?.name;
  @override
  String? get lastError => _lastError;
  @override
  String get localDeviceId => _identity?.deviceId ?? initialDeviceId ?? '';
  @override
  String get localName => settings.deviceName ?? name;
  @override
  ValueListenable<Map<String, double>> get transfers => _files.progress;
  @override
  Stream<SyncEvent> get events => _events.stream;

  void _emit(SyncEvent event) {
    if (!_disposed) _events.add(event);
  }

  void _setStatus(ConnectionStatus value, [String? error]) {
    if (_disposed) return;
    final changed = _status != value || _lastError != error;
    _status = value;
    _lastError = error;
    if (changed) notifyListeners();
  }

  void _repositoryChanged() {
    if (_running && _active?.hello == true) {
      if (_flushing) {
        _flushAgain = true;
        return;
      }
      _background(syncNow());
    }
  }

  void _settingsChanged() {
    if (!settings.autoReconnect) {
      _reconnectTimer?.cancel();
    } else if (_running && _active == null) {
      _scheduleReconnect();
    }
  }

  void _background(Future<void> future) {
    future.catchError((Object error, StackTrace stack) {
      if (_running) {
        _setStatus(
          ConnectionStatus.failed,
          'Verbinden lukt nog niet. Probeer opnieuw.',
        );
      }
    });
  }

  Future<Directory> _downloadDirectory() async {
    if (receiveDirectory != null) return receiveDirectory!();
    if (isHost) {
      return Directory(
        settings.downloadDir ??
            p.join(
              Platform.environment['HOME'] ?? supportDirectory.path,
              'Downloads',
              'DOT',
            ),
      );
    }
    return Directory(
      p.join((await getApplicationDocumentsDirectory()).path, 'received'),
    );
  }

  Future<bool> _hasNetwork() async {
    if (networkAvailable != null) return networkAvailable!();
    if (advertisedHost != null) return true;
    return await lanIPv4() != null;
  }

  @override
  Future<void> start() async {
    if (_running || _disposed) return;
    _running = true;
    final generation = ++_generation;
    try {
      _identity ??= await DeviceIdentity.load(
        secrets,
        initialDeviceId: initialDeviceId,
      );
      if (!_running || generation != _generation) return;
      if (isHost) {
        _certificate ??= await TlsCertificate.load(secrets);
        await _server.start(
          _certificate!,
          _accept,
          bindAddress: bindAddress,
          preferredPort: preferredPort,
        );
        try {
          await discovery.advertise(localDeviceId, localName, _server.port);
        } catch (_) {
          /* Manual route remains available. */
        }
      } else {
        try {
          await discovery.discover(_discovered);
        } catch (_) {
          /* Last known address remains available. */
        }
      }
      if (!_running || generation != _generation) {
        await _server.stop();
        await discovery.stop();
        return;
      }
      _transportReady = true;
      _setStatus(
        devices.hasPeer
            ? ConnectionStatus.searching
            : ConnectionStatus.unpaired,
      );
      if (devices.hasPeer && settings.autoReconnect) await reconnect();
    } catch (e) {
      debugPrint('DOT sync start failed: ${e.runtimeType}: $e');
      _setStatus(
        ConnectionStatus.failed,
        'DOT kan de beveiligde verbinding niet starten. Probeer opnieuw.',
      );
      await _server.stop();
      _scheduleReconnect();
    }
  }

  void _discovered(HostAddress address) {
    _hosts[address.deviceId] = address;
    if (_running &&
        _activeApp &&
        settings.autoReconnect &&
        devices.get(address.deviceId) != null &&
        _active == null) {
      _background(reconnect());
    }
  }

  @override
  Future<void> stop() async {
    _running = false;
    _transportReady = false;
    ++_generation;
    _reconnectTimer?.cancel();
    _offerTimer?.cancel();
    tokens.cancel();
    _requests.clear();
    final sessions = _sessions.toList();
    for (final session in sessions) {
      await _close(session, 'Verbinding gestopt.');
    }
    for (final session in sessions) {
      await session.queue;
    }
    await _files.disconnected();
    _inFlight.clear();
    await _server.stop();
    try {
      await discovery.stop();
    } catch (_) {}
    await repository.setStateForDirty(SyncState.waiting);
    _setStatus(
      devices.hasPeer ? ConnectionStatus.offline : ConnectionStatus.unpaired,
    );
  }

  @override
  Future<void> onAppLifecycle({required bool active}) async {
    _activeApp = active;
    if (!active) {
      await stop();
    } else {
      await start();
    }
  }

  @override
  Future<PairingOffer> createPairingOffer() async {
    if (!isHost) throw StateError('Koppelen start op je MacBook.');
    if (!_running) await start();
    if (_certificate == null || !_transportReady) {
      throw StateError('Beveiligde verbinding is niet beschikbaar.');
    }
    final host = advertisedHost ?? await lanIPv4();
    if (host == null) {
      _setStatus(ConnectionStatus.offline);
      throw StateError('Verbind je MacBook met een lokaal netwerk.');
    }
    await cancelPairingOffer();
    tokens.issue();
    _offerTimer = Timer(const Duration(minutes: 5), () {
      _background(cancelPairingOffer());
    });
    final uri = Uri(
      scheme: 'dot',
      host: 'pair',
      queryParameters: {
        'h': host,
        'p': '${_server.port}',
        't': tokens.token!,
        'f': _certificate!.fingerprint,
        'n': localName,
        'id': localDeviceId,
      },
    );
    _setStatus(ConnectionStatus.pairing);
    return PairingOffer(
      qrPayload: uri.toString(),
      manualCode: tokens.code!,
      host: host,
      port: _server.port,
      expiresAt: tokens.expiresAt!,
    );
  }

  @override
  Future<void> cancelPairingOffer() async {
    tokens.cancel();
    _offerTimer?.cancel();
    for (final entry in _requests.entries.toList()) {
      entry.value.session.send('pair_result', {
        'requestId': entry.key,
        'accepted': false,
      });
      await _close(entry.value.session, 'Koppelen geannuleerd.');
    }
    _requests.clear();
    if (_running) {
      _setStatus(
        _active != null
            ? ConnectionStatus.connected
            : devices.hasPeer
            ? ConnectionStatus.searching
            : ConnectionStatus.unpaired,
      );
    }
  }

  @override
  Future<PairingPreview> previewPairing(String qrPayloadOrManual) async {
    final input = qrPayloadOrManual.trim();
    if (input.startsWith('dot://')) {
      final uri = Uri.parse(input);
      final q = uri.queryParameters;
      final port = int.tryParse(q['p'] ?? '');
      if (uri.host != 'pair' ||
          q['h']?.isNotEmpty != true ||
          port == null ||
          port < 1 ||
          port > 65535 ||
          q['t']?.isNotEmpty != true ||
          !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(q['f'] ?? '') ||
          q['id']?.isNotEmpty != true) {
        throw const FormatException('Deze koppelcode is ongeldig.');
      }
      return PairingPreview(
        host: q['h']!,
        port: port,
        token: q['t']!,
        certFingerprint: q['f']!.toLowerCase(),
        peerName: q['n'] ?? 'MacBook',
        peerId: q['id'],
      );
    }
    final match = RegExp(r'^([0-9.]+):(\d+)\s+([A-Za-z0-9]{6})$')
        .firstMatch(input);
    if (match == null) {
      throw const FormatException(
        'Gebruik IP:poort CODE, bijvoorbeeld 192.168.1.20:48620 ABC123.',
      );
    }
    final host = match[1]!;
    final port = int.parse(match[2]!);
    final code = match[3]!.toUpperCase();
    if (InternetAddress.tryParse(host)?.type != InternetAddressType.IPv4 ||
        port < 1 ||
        port > 65535) {
      throw const FormatException('Ongeldig adres.');
    }
    final pin = await ClientConnection.probeFingerprint(host, port);
    final connection = await ClientConnection.connect(host, port, pin);
    final nonce = randomNonce();
    try {
      final reply = Completer<Map<String, dynamic>>();
      final subscription = connection.socket.listen(
        (frame) {
          if (frame is String) {
            final message = decodeMessage(frame);
            if (message['t'] == 'manual_proof' && !reply.isCompleted) {
              reply.complete(message);
            }
          }
        },
        onDone: () {
          if (!reply.isCompleted) {
            reply.completeError(StateError('Koppelcode verlopen.'));
          }
        },
        onError: (Object error) {
          if (!reply.isCompleted) reply.completeError(error);
        },
      );
      connection.socket.add(encodeMessage('manual_probe', {'nonce': nonce}));
      final message = await reply.future.timeout(const Duration(seconds: 10));
      await subscription.cancel();
      final id = message['deviceId'] as String;
      final name = message['name'] as String;
      final expected = manualProof(code, nonce, pin, id, name);
      if (message['proof'] != expected) {
        throw StateError('De koppelcode klopt niet of is verlopen.');
      }
      return PairingPreview(
        host: host,
        port: port,
        token: code,
        certFingerprint: pin,
        peerName: name,
        peerId: id,
      );
    } finally {
      await connection.close();
    }
  }

  @override
  Future<PairedDevice> confirmPairing(PairingPreview preview) async {
    if (isHost) throw StateError('Scan de code op je Android-apparaat.');
    if (!_running) await start();
    if (preview.certFingerprint == null || preview.peerId == null) {
      throw StateError('De identiteit van de MacBook ontbreekt.');
    }
    _setStatus(ConnectionStatus.pairing);
    try {
      final session = await _connect(
        preview.host,
        preview.port,
        preview.certFingerprint!,
        preview: preview,
      );
      return await session.ready.future.timeout(
        const Duration(minutes: 5),
        onTimeout: () async {
          await _close(session, 'Koppelen verlopen.');
          throw TimeoutException('Koppelen verlopen.');
        },
      );
    } catch (_) {
      _setStatus(
        ConnectionStatus.failed,
        'Koppelen lukt niet. Controleer de code en probeer opnieuw.',
      );
      _emit(
        const PairingFailedEvent(
          'Koppelen lukt niet. Controleer de code en probeer opnieuw.',
        ),
      );
      rethrow;
    }
  }

  void _accept(WebSocket socket) {
    if (!_running || !_activeApp || _sessions.length >= 8) {
      socket.close(WebSocketStatus.policyViolation, 'Niet beschikbaar.');
      return;
    }
    final session = _Session(socket);
    _attach(session);
    session.send('challenge', {'nonce': session.challenge});
  }

  Future<_Session> _connect(
    String host,
    int port,
    String pin, {
    PairingPreview? preview,
  }) async {
    final generation = _generation;
    final connection = await ClientConnection.connect(host, port, pin);
    if (!_running || generation != _generation) {
      await connection.close();
      throw StateError('Verbinding gestopt.');
    }
    final session = _Session(
      connection.socket,
      client: connection,
      preview: preview,
    );
    _attach(session);
    return session;
  }

  void _attach(_Session session) {
    _sessions.add(session);
    session.deadline = Timer(const Duration(seconds: 15), () {
      if (!session.authenticated &&
          !_requests.values.any((r) => r.session == session)) {
        _background(_close(session, 'Identiteit niet bevestigd.'));
      }
    });
    session.socket.listen(
      (frame) {
        session.queue = session.queue
            .then((_) async {
              if (session.closed) return;
              session.lastSeen = DateTime.now();
              if (frame is String) {
                await _handle(session, decodeMessage(frame));
              } else if (frame is List<int> &&
                  session == _active &&
                  session.authenticated &&
                  session.hello) {
                await _files.receiveChunk(frame);
              } else {
                throw const FormatException('Onverwacht bericht.');
              }
            })
            .catchError((Object error, StackTrace stack) async {
              if (session == _active || session.client != null) {
                _setStatus(
                  ConnectionStatus.failed,
                  'De verbinding is ongeldig of onderbroken. Probeer opnieuw.',
                );
              }
              await _close(session, 'Ongeldig bericht.');
            });
      },
      onDone: () {
        _background(_closed(session));
      },
      onError: (Object error) {
        _background(_close(session, 'Verbinding onderbroken.'));
      },
    );
  }

  Future<void> _handle(_Session session, Map<String, dynamic> message) async {
    final type = message['t'];
    if (type == 'manual_probe' && isHost && !session.authenticated) {
      if (!tokens.valid ||
          DateTime.now().difference(session.createdAt).inSeconds > 15) {
        await _close(session, 'Koppelcode verlopen.');
        return;
      }
      final nonce = message['nonce'] as String;
      session.send('manual_proof', {
        'deviceId': localDeviceId,
        'name': localName,
        'proof': manualProof(
          tokens.code!,
          nonce,
          _certificate!.fingerprint,
          localDeviceId,
          localName,
        ),
      });
      return;
    }
    if (type == 'challenge' && !isHost && !session.authenticated) {
      final nonce = message['nonce'] as String;
      if (nonce.length < 20 || nonce.length > 200) {
        throw const FormatException('Ongeldige uitdaging.');
      }
      final preview = session.preview;
      if (preview != null) {
        session.deadline?.cancel();
        session.deadline = Timer(const Duration(minutes: 5), () {
          _background(_close(session, 'Koppelen verlopen.'));
        });
        session.send('pair', {
          'requestId': session.requestId,
          'token': preview.token,
          'deviceId': localDeviceId,
          'name': localName,
          'platform': 'android',
          'pubKey': _identity!.publicKey,
          'nonce': nonce,
          'sig': await _identity!.sign('client:$nonce'),
          'clientNonce': session.clientNonce,
        });
      } else {
        session.send('auth', {
          'deviceId': localDeviceId,
          'nonce': nonce,
          'sig': await _identity!.sign('client:$nonce'),
          'clientNonce': session.clientNonce,
        });
      }
      return;
    }
    if (type == 'pair' && isHost && !session.authenticated) {
      final requestId = message['requestId'] as String;
      final token = message['token'] as String;
      if (_requests.containsKey(requestId) ||
          _requests.values.any((r) => r.session == session) ||
          !tokens.matches(token) ||
          message['nonce'] != session.challenge ||
          !await DeviceIdentity.verify(
            message['pubKey'] as String,
            'client:${session.challenge}',
            message['sig'] as String,
          )) {
        await _close(session, 'Koppelcode ongeldig of verlopen.');
        return;
      }
      final id = message['deviceId'] as String;
      if (id == localDeviceId ||
          base64Decode(message['pubKey'] as String).length != 32) {
        throw const FormatException('Ongeldige identiteit.');
      }
      final peer = PairedDevice(
        id: id,
        name: message['name'] as String,
        platform: platformFromString(message['platform'] as String),
        publicKey: message['pubKey'] as String,
        pairedAt: DateTime.now(),
      );
      _requests[requestId] = _PairRequest(session, peer, token);
      // Keep the fresh client challenge in the session without accepting data.
      _clientChallenges[session] = message['clientNonce'] as String;
      session.deadline?.cancel();
      session.deadline = Timer(
        tokens.expiresAt!.difference(DateTime.now()),
        () {
          _background(_close(session, 'Koppelen verlopen.'));
        },
      );
      _setStatus(ConnectionStatus.pairing);
      _emit(
        PairRequestEvent(
          PairingRequest(
            requestId: requestId,
            deviceName: peer.name,
            platform: peer.platform,
          ),
        ),
      );
      return;
    }
    if (type == 'pair_result' &&
        !isHost &&
        session.preview != null &&
        !session.authenticated) {
      if (message['requestId'] != session.requestId) {
        throw const FormatException('Ongeldig koppelverzoek.');
      }
      if (message['accepted'] != true) {
        await _close(session, 'Koppelen afgewezen.');
        return;
      }
      if (message['deviceId'] != session.preview!.peerId ||
          !await DeviceIdentity.verify(
            message['pubKey'] as String,
            'host:${session.clientNonce}',
            message['sig'] as String,
          )) {
        await _close(session, 'Identiteit komt niet overeen.');
        return;
      }
      final preview = session.preview!;
      final peer = PairedDevice(
        id: message['deviceId'] as String,
        name: message['name'] as String,
        platform: DevicePlatform.macos,
        publicKey: message['pubKey'] as String,
        certFingerprint: preview.certFingerprint,
        host: preview.host,
        port: preview.port,
        pairedAt: DateTime.now(),
        lastConnectedAt: DateTime.now(),
      );
      await devices.save(peer);
      _emit(PairedEvent(peer));
      await _authenticated(session, peer);
      return;
    }
    if (type == 'auth' && !session.authenticated) {
      if (isHost) {
        final peer = devices.get(message['deviceId'] as String);
        if (peer == null ||
            message['nonce'] != session.challenge ||
            !await DeviceIdentity.verify(
              peer.publicKey,
              'client:${session.challenge}',
              message['sig'] as String,
            )) {
          await _close(session, 'Onbekend of ingetrokken apparaat.');
          return;
        }
        session.send('auth', {
          'deviceId': localDeviceId,
          'nonce': message['clientNonce'],
          'sig': await _identity!.sign('host:${message['clientNonce']}'),
        });
        await _authenticated(session, peer);
      } else {
        final peer = devices.get(message['deviceId'] as String);
        if (peer == null ||
            peer.id != devices.primary?.id ||
            message['nonce'] != session.clientNonce ||
            !await DeviceIdentity.verify(
              peer.publicKey,
              'host:${session.clientNonce}',
              message['sig'] as String,
            )) {
          await _close(session, 'Onbekend of ingetrokken apparaat.');
          return;
        }
        await _authenticated(session, peer);
      }
      return;
    }
    if (!session.authenticated) {
      await _close(session, 'Onbekend of ingetrokken apparaat.');
      return;
    }
    if (session.peer == null || devices.get(session.peer!.id) == null) {
      await _close(session, 'Koppeling ingetrokken.');
      return;
    }
    if (type == 'hello') {
      if (message['deviceId'] != session.peer!.id ||
          message['proto'] != protocolVersion) {
        _setStatus(
          ConnectionStatus.failed,
          'Deze DOT-versies kunnen niet verbinden. Werk beide apps bij.',
        );
        await _close(session, 'Protocolversie komt niet overeen.');
        return;
      }
      session.hello = true;
      if (!session.ready.isCompleted) session.ready.complete(session.peer!);
      await syncNow();
      return;
    }
    if (type == 'ping') {
      session.send('pong');
      return;
    }
    if (type == 'pong') return;
    if (type == 'unpair') {
      if (message['deviceId'] != localDeviceId &&
          message['deviceId'] != session.peer!.id) {
        throw const FormatException('Ongeldig apparaat.');
      }
      await devices.remove(session.peer!.id);
      await _close(session, 'Koppeling verwijderd.');
      _setStatus(ConnectionStatus.unpaired);
      return;
    }
    if (!session.hello || session != _active) {
      throw const FormatException('Verbinding is nog niet gereed.');
    }
    switch (type) {
      case 'item':
        final item = DotItem.fromWire(
          Map<String, Object?>.from(message['item'] as Map),
        );
        if (item == null) return;
        await repository.applyRemote(item);
        if (item.type != ItemType.file || item.deleted) {
          session.send('ack', {'id': item.id, 'etag': item.etag});
          _emit(ItemReceivedEvent(item.id));
        } else {
          final stored = await repository.get(item.id);
          if (stored?.localPath == null && stored?.deleted != true) {
            await repository.setSyncState(item.id, SyncState.waiting);
          }
        }
      case 'ack':
        final id = message['id'] as String;
        final etag = message['etag'] as String;
        if (_inFlight[id] == etag) {
          _inFlight.remove(id);
          await repository.markSynced(id, etag);
          _emit(ItemSentEvent(id));
        }
      case 'file_offer':
        await _files.receiveOffer(message);
      case 'file_resume':
        await _files.resume(message);
      case 'file_done':
        await _files.done(message);
      case 'file_ack':
        await _files.acknowledge(message);
      case 'file_retry':
        final id = message['id'] as String;
        final item = await repository.get(id);
        if (item != null &&
            !item.deleted &&
            item.type == ItemType.file &&
            item.localPath != null) {
          _inFlight[id] = item.etag;
          session.send('item', {'item': item.toWire()});
          await _files.offer(item);
        }
      case 'file_cancel':
        _inFlight.remove(message['id']);
        await _files.cancel(message['id'] as String, notifyPeer: false);
      default:
        break;
    }
    _settleStatus();
  }

  final Map<_Session, String> _clientChallenges = {};
  @override
  Future<void> respondToPairRequest(String requestId, bool accept) async {
    final request = _requests.remove(requestId);
    if (request == null || request.session.closed) {
      throw StateError('Koppelverzoek verlopen.');
    }
    final session = request.session;
    if (!accept || !tokens.consume(request.token)) {
      session.send('pair_result', {'requestId': requestId, 'accepted': false});
      await _close(session, 'Koppelen afgewezen of verlopen.');
      return;
    }
    _offerTimer?.cancel();
    await devices.save(request.device);
    session.send('pair_result', {
      'requestId': requestId,
      'accepted': true,
      'deviceId': localDeviceId,
      'name': localName,
      'pubKey': _identity!.publicKey,
      'sig': await _identity!.sign('host:${_clientChallenges[session]}'),
    });
    _emit(PairedEvent(request.device));
    await _authenticated(session, request.device);
    // A token can approve exactly one request, including simultaneous scans.
    for (final other in _requests.values.toList()) {
      await _close(other.session, 'Koppelcode al gebruikt.');
    }
    _requests.clear();
  }

  Future<void> _authenticated(_Session session, PairedDevice peer) async {
    if (_active != null && _active != session) {
      await _close(_active!, 'Nieuwe verbinding.');
    }
    session.peer = peer;
    session.authenticated = true;
    session.deadline?.cancel();
    session.deadline = Timer(const Duration(seconds: 15), () {
      if (!session.hello) {
        _background(_close(session, 'Verbinding niet gereed.'));
      }
    });
    _active = session;
    _peerName = peer.name;
    _backoff = 1;
    _reconnectTimer?.cancel();
    await devices.update(peer.copyWith(lastConnectedAt: DateTime.now()));
    session.send('hello', {
      'deviceId': localDeviceId,
      'name': localName,
      'platform': isHost ? 'macos' : 'android',
      'proto': protocolVersion,
      'app': '1.0.0',
    });
    var lastPing = DateTime.now();
    session.heartbeat = Timer.periodic(const Duration(seconds: 5), (_) {
      if (DateTime.now().difference(session.lastSeen).inSeconds >= 40) {
        _background(_close(session, 'Verbinding reageert niet.'));
      } else if (DateTime.now().difference(lastPing).inSeconds >= 15) {
        lastPing = DateTime.now();
        session.send('ping');
      }
    });
    _setStatus(ConnectionStatus.connected);
  }

  @override
  Future<void> reconnect() async {
    if (!_running || !_activeApp || _connecting || _active != null) return;
    _reconnectTimer?.cancel();
    if (!_transportReady) {
      _running = false;
      await start();
      return;
    }
    if (!await _hasNetwork()) {
      _setStatus(ConnectionStatus.offline);
      await repository.setStateForDirty(SyncState.waiting);
      _scheduleReconnect();
      return;
    }
    if (!devices.hasPeer) {
      _setStatus(ConnectionStatus.unpaired);
      return;
    }
    _setStatus(ConnectionStatus.searching);
    if (isHost) {
      await repository.setStateForDirty(SyncState.waiting);
      _scheduleReconnect();
      return;
    }
    _connecting = true;
    _Session? session;
    try {
      final peer = devices.primary!;
      final found = _hosts[peer.id];
      final host = found?.host ?? peer.host;
      final port = found?.port ?? peer.port;
      if (host == null || port == null || peer.certFingerprint == null) {
        throw StateError('Geen bekend adres.');
      }
      session = await _connect(host, port, peer.certFingerprint!);
      await session.ready.future.timeout(const Duration(seconds: 15));
      await devices.update(
        peer.copyWith(host: host, port: port, lastConnectedAt: DateTime.now()),
      );
    } catch (_) {
      if (session != null) await _close(session, 'Verbinden mislukt.');
      if (_running) {
        _setStatus(
          ConnectionStatus.failed,
          'Je apparaat is niet bereikbaar. DOT probeert opnieuw te verbinden.',
        );
        await repository.setStateForDirty(SyncState.waiting);
        _scheduleReconnect();
      }
    } finally {
      _connecting = false;
    }
  }

  void _scheduleReconnect() {
    if (!_running ||
        !_activeApp ||
        !settings.autoReconnect ||
        _active != null ||
        _disposed) {
      return;
    }
    if (_reconnectTimer?.isActive == true) return;
    _reconnectTimer = Timer(Duration(seconds: _backoff), () {
      _background(reconnect());
    });
    _backoff = (_backoff * 2).clamp(1, 30);
  }

  @override
  Future<void> syncNow() async {
    if (_flushing) {
      _flushAgain = true;
      return;
    }
    final session = _active;
    if (session == null ||
        !session.authenticated ||
        !session.hello ||
        session.closed) {
      await repository.setStateForDirty(SyncState.waiting);
      return;
    }
    _flushing = true;
    try {
      do {
        _flushAgain = false;
        for (final item in await repository.pending()) {
          if (_active != session || session.closed) break;
          if (_inFlight[item.id] == item.etag) continue;
          // Do not replace a transfer while a previous version is in flight.
          if (_inFlight.containsKey(item.id)) continue;
          if (item.syncState == SyncState.failed) continue;
          _inFlight[item.id] = item.etag;
          _setStatus(ConnectionStatus.syncing);
          await repository.setSyncState(item.id, SyncState.sending);
          session.send('item', {'item': item.toWire()});
          if (item.type == ItemType.file && !item.deleted) {
            await _files.offer(item);
          }
        }
      } while (_flushAgain && _active == session);
    } finally {
      _flushing = false;
      _settleStatus();
    }
  }

  void _settleStatus() {
    if (_active?.hello == true) {
      _setStatus(
        _inFlight.isNotEmpty || _files.busy
            ? ConnectionStatus.syncing
            : ConnectionStatus.connected,
      );
    }
  }

  @override
  Future<void> unpair(String deviceId) async {
    final session = _active;
    if (session?.peer?.id == deviceId) {
      session!.send('unpair', {'deviceId': localDeviceId});
    }
    await devices.remove(deviceId);
    for (final connection
        in _sessions.where((s) => s.peer?.id == deviceId).toList()) {
      await _close(connection, 'Koppeling verwijderd.');
    }
    _setStatus(
      devices.hasPeer ? ConnectionStatus.searching : ConnectionStatus.unpaired,
    );
  }

  @override
  Future<void> cancelTransfer(String itemId) async {
    // Keep the flight marker until cancellation is sent to prevent the
    // repository's state notification automatically starting it again.
    await _files.cancel(itemId);
    _inFlight.remove(itemId);
    _settleStatus();
  }

  @override
  Future<void> retry(String itemId) async {
    _inFlight.remove(itemId);
    await repository.setSyncState(itemId, SyncState.waiting);
    final item = await repository.get(itemId);
    if (item != null && !item.dirty && item.type == ItemType.file) {
      // A receiving device asks the sender to retry its durable file offer.
      _active?.send('file_retry', {'id': itemId});
    }
    await syncNow();
    if (_active == null) await reconnect();
  }

  Future<void> _close(_Session session, String reason) async {
    if (session.closed) return;
    session.closed = true;
    await _closed(session);
    try {
      await session.socket
          .close(WebSocketStatus.policyViolation, reason)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    session.client?.client.close(force: true);
  }

  Future<void> _closed(_Session session) async {
    if (!_sessions.remove(session)) return;
    session.closed = true;
    session.deadline?.cancel();
    session.heartbeat?.cancel();
    _clientChallenges.remove(session);
    _requests.removeWhere((_, request) => request.session == session);
    if (!session.ready.isCompleted) {
      session.ready.completeError(StateError('Verbinding beëindigd.'));
    }
    if (_active == session) {
      _active = null;
      _inFlight.clear();
      await _files.disconnected();
      await repository.setStateForDirty(SyncState.waiting);
      if (_running) {
        if (_status != ConnectionStatus.failed) {
          _setStatus(
            devices.hasPeer
                ? ConnectionStatus.searching
                : ConnectionStatus.unpaired,
          );
        }
        _scheduleReconnect();
      }
    }
    session.client?.client.close(force: true);
  }

  @override
  void dispose() {
    if (_disposed) return;
    repository.removeListener(_repositoryChanged);
    settings.removeListener(_settingsChanged);
    _disposed = true;
    _running = false;
    ++_generation;
    _reconnectTimer?.cancel();
    _offerTimer?.cancel();
    for (final session in _sessions) {
      session.closed = true;
      session.deadline?.cancel();
      session.heartbeat?.cancel();
      session.socket.close();
      session.client?.client.close(force: true);
      if (!session.ready.isCompleted) {
        session.ready.completeError(StateError('DOT afgesloten.'));
      }
    }
    _sessions.clear();
    _server.stop();
    discovery.stop().catchError((Object _) {});
    _events.close();
    _files.dispose();
    super.dispose();
  }
}
