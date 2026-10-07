import 'package:flutter/foundation.dart';

import 'models.dart';
import 'remote_input.dart';

abstract class SyncEngine extends ChangeNotifier {
  ConnectionStatus get status;
  String? get peerName;
  String? get lastError;
  String get localDeviceId;
  String get localName;
  bool get isHost;
  ValueListenable<Map<String, double>> get transfers;
  ValueListenable<RemoteInputStatus> get remoteStatus;
  void sendInput(RemoteInput input);
  Stream<SyncEvent> get events;
  Future<void> start();
  Future<void> stop();
  Future<PairingOffer> createPairingOffer();
  Future<PairingPreview> previewPairing(String qrPayloadOrManual);
  Future<PairedDevice> confirmPairing(PairingPreview preview);
  Future<void> respondToPairRequest(String requestId, bool accept);
  Future<void> cancelPairingOffer();
  Future<void> onAppLifecycle({required bool active});
  Future<void> reconnect();
  Future<void> unpair(String deviceId);
  Future<void> syncNow();
  Future<void> cancelTransfer(String itemId);
  Future<void> retry(String itemId);
}
