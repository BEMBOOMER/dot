import 'dart:async';

import 'package:flutter/foundation.dart';

import 'device_store.dart';
import 'item_repository.dart';
import 'models.dart';
import 'remote_input.dart';
import 'sync_engine.dart';

/// Demo transport only: never discovers or contacts a real device.
class FakeSyncEngine extends SyncEngine {
  final ItemRepository repository;
  final DeviceStore devices;
  @override
  final String localDeviceId;
  @override
  final String localName;
  @override
  final bool isHost;
  final Duration connectionDelay;
  final Duration sendDelay;
  FakeSyncEngine({
    required this.repository,
    required this.devices,
    required this.localDeviceId,
    required this.localName,
    this.isHost = true,
    this.connectionDelay = const Duration(milliseconds: 500),
    this.sendDelay = const Duration(milliseconds: 800),
  });
  ConnectionStatus _status = ConnectionStatus.unpaired;
  bool _running = false;
  bool _syncing = false;
  Future<void>? _syncFuture;
  int _generation = 0;
  final Set<String> _cancelled = {};
  final _events = StreamController<SyncEvent>.broadcast();
  final _transfers = ValueNotifier<Map<String, double>>(const {});
  // Demo mode never controls the real computer.
  final _remoteStatus = ValueNotifier(const RemoteInputStatus());
  @override
  ValueListenable<RemoteInputStatus> get remoteStatus => _remoteStatus;
  @override
  void sendInput(RemoteInput input) {}
  @override
  ConnectionStatus get status => _status;
  @override
  String? get peerName => 'Demo-apparaat';
  @override
  String? get lastError => null;
  @override
  Stream<SyncEvent> get events => _events.stream;
  @override
  ValueListenable<Map<String, double>> get transfers => _transfers;
  void _setStatus(ConnectionStatus value) {
    _status = value;
    notifyListeners();
  }

  @override
  Future<void> start() async {
    _running = true;
    final generation = ++_generation;
    _setStatus(ConnectionStatus.searching);
    await Future<void>.delayed(connectionDelay);
    if (!_running || generation != _generation) return;
    _setStatus(ConnectionStatus.connected);
    await syncNow();
  }

  @override
  Future<void> stop() async {
    _running = false;
    ++_generation;
    _transfers.value = const {};
    _setStatus(ConnectionStatus.offline);
    await _syncFuture;
  }

  @override
  Future<void> syncNow() {
    if (_syncFuture != null) return _syncFuture!;
    final future = _flush();
    _syncFuture = future;
    return future.whenComplete(() {
      _syncFuture = null;
    });
  }

  Future<void> _flush() async {
    if (!_running || _syncing || status == ConnectionStatus.searching) return;
    _syncing = true;
    final generation = _generation;
    try {
      while (_running && generation == _generation) {
        final pending = (await repository.pending())
            .where((i) => !_cancelled.contains(i.id))
            .toList();
        if (pending.isEmpty) break;
        _setStatus(ConnectionStatus.syncing);
        for (final item in pending) {
          if (!_running || generation != _generation) break;
          await repository.setSyncState(item.id, SyncState.sending);
          _transfers.value = Map<String, double>.unmodifiable({
            ..._transfers.value,
            item.id: 0.0,
          });
          await Future<void>.delayed(sendDelay);
          if (!_running || generation != _generation) break;
          if (!_cancelled.contains(item.id)) {
            await repository.markSynced(item.id, item.etag);
            _events.add(ItemSentEvent(item.id));
          }
          _transfers.value = Map<String, double>.unmodifiable(
            {..._transfers.value}..remove(item.id),
          );
        }
      }
    } finally {
      _syncing = false;
      if (_running && generation == _generation) {
        _setStatus(ConnectionStatus.connected);
      }
    }
  }

  Future<void> simulateIncoming([DotItem? item]) async {
    final now = DateTime.now();
    final incoming =
        item ??
        DotItem(
          id: newId(),
          type: ItemType.text,
          title: 'Hallo van je demo-apparaat',
          body: 'Je werkruimte is verbonden.',
          originDeviceId: 'demo-peer',
          originName: 'Demo-apparaat',
          createdAt: now,
          updatedAt: now,
          etag: newId(),
        );
    await repository.applyRemote(incoming);
    _events.add(ItemReceivedEvent(incoming.id));
  }

  @override
  Future<PairingOffer> createPairingOffer() async {
    _setStatus(ConnectionStatus.pairing);
    return PairingOffer(
      qrPayload:
          'dot://pair?h=127.0.0.1&p=0&t=DEMO01&n=Demo-apparaat&id=demo-peer',
      manualCode: 'DEMO01',
      host: '127.0.0.1',
      port: 0,
      expiresAt: DateTime.now().add(const Duration(minutes: 5)),
    );
  }

  @override
  Future<PairingPreview> previewPairing(String qrPayloadOrManual) async =>
      const PairingPreview(
        host: '127.0.0.1',
        port: 0,
        token: 'DEMO01',
        certFingerprint: null,
        peerName: 'Demo-apparaat',
        peerId: 'demo-peer',
      );
  @override
  Future<PairedDevice> confirmPairing(PairingPreview preview) async {
    final device = PairedDevice(
      id: 'demo-peer',
      name: preview.peerName,
      platform: isHost ? DevicePlatform.android : DevicePlatform.macos,
      publicKey: '',
      pairedAt: DateTime.now(),
    );
    await devices.save(device);
    _events.add(PairedEvent(device));
    await start();
    return device;
  }

  @override
  Future<void> respondToPairRequest(String requestId, bool accept) async {
    if (accept) {
      await confirmPairing(await previewPairing('demo'));
    } else {
      await cancelPairingOffer();
    }
  }

  @override
  Future<void> cancelPairingOffer() async => _setStatus(
    _running ? ConnectionStatus.connected : ConnectionStatus.unpaired,
  );
  @override
  Future<void> onAppLifecycle({required bool active}) async {
    if (active) {
      await start();
    } else {
      await stop();
    }
  }

  @override
  Future<void> reconnect() => start();
  @override
  Future<void> unpair(String deviceId) async {
    await devices.remove(deviceId);
    await stop();
    _setStatus(ConnectionStatus.unpaired);
  }

  @override
  Future<void> cancelTransfer(String itemId) async {
    _cancelled.add(itemId);
    await repository.setSyncState(itemId, SyncState.failed);
    _transfers.value = Map<String, double>.unmodifiable(
      {..._transfers.value}..remove(itemId),
    );
  }

  @override
  Future<void> retry(String itemId) async {
    _cancelled.remove(itemId);
    await syncNow();
  }

  @override
  void dispose() {
    _running = false;
    ++_generation;
    _events.close();
    _transfers.dispose();
    _remoteStatus.dispose();
    super.dispose();
  }
}
