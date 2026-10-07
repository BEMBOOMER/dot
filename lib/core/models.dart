import 'dart:convert';

enum ItemType { text, link, file, note }

/// Where an item is in its journey to the paired device.
enum SyncState { local, waiting, sending, received, failed }

enum ConnectionStatus { unpaired, searching, pairing, connected, syncing, offline, failed }

enum DevicePlatform { android, macos, unknown }

String itemTypeLabel(ItemType t) => switch (t) {
      ItemType.text => 'Tekst',
      ItemType.link => 'Link',
      ItemType.file => 'Bestand',
      ItemType.note => 'Notitie',
    };

String syncStateLabel(SyncState s) => switch (s) {
      SyncState.local => 'Lokaal opgeslagen',
      SyncState.waiting => 'Wacht op verbinding',
      SyncState.sending => 'Versturen',
      SyncState.received => 'Ontvangen',
      SyncState.failed => 'Versturen mislukt',
    };

/// Dutch status line. [peerName] is the paired device's name, e.g. "MacBook".
String statusLabel(ConnectionStatus s, {String? peerName}) {
  final peer = (peerName == null || peerName.isEmpty) ? 'je apparaat' : peerName;
  return switch (s) {
    ConnectionStatus.unpaired => 'Koppel je apparaat',
    ConnectionStatus.searching => '${_cap(peer)} zoeken…',
    ConnectionStatus.pairing => 'Bevestig de verbinding',
    ConnectionStatus.connected => 'Verbonden met $peer',
    ConnectionStatus.syncing => 'Wijzigingen synchroniseren…',
    ConnectionStatus.offline => 'Je apparaat is offline',
    ConnectionStatus.failed => 'Verbinden lukt nog niet',
  };
}

String _cap(String s) => s == 'je apparaat' ? 'Je apparaat' : s;

DevicePlatform platformFromString(String? s) => switch (s) {
      'android' => DevicePlatform.android,
      'macos' => DevicePlatform.macos,
      _ => DevicePlatform.unknown,
    };

class DotItem {
  final String id;
  final ItemType type;
  final String title;

  /// Text content, note body or URL (for links).
  final String body;

  /// File metadata (type == file).
  final String? fileName;
  final int? fileSize;
  final String? mimeType;
  final String? sha256;

  /// Absolute path on THIS device (null until a received file is complete).
  final String? localPath;

  final String originDeviceId;
  final String originName;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool pinned;
  final bool deleted;
  final String etag;
  final String? parentEtag;

  /// Needs to be sent to the peer.
  final bool dirty;
  final SyncState syncState;

  /// 0..1 while a file is transferring.
  final double progress;

  /// Set on a conflict copy of a note: the id of the original note.
  final String? conflictOf;

  const DotItem({
    required this.id,
    required this.type,
    required this.title,
    required this.body,
    this.fileName,
    this.fileSize,
    this.mimeType,
    this.sha256,
    this.localPath,
    required this.originDeviceId,
    required this.originName,
    required this.createdAt,
    required this.updatedAt,
    this.pinned = false,
    this.deleted = false,
    required this.etag,
    this.parentEtag,
    this.dirty = false,
    this.syncState = SyncState.local,
    this.progress = 0,
    this.conflictOf,
  });

  DotItem copyWith({
    String? title,
    String? body,
    String? fileName,
    int? fileSize,
    String? mimeType,
    String? sha256,
    String? localPath,
    DateTime? updatedAt,
    bool? pinned,
    bool? deleted,
    String? etag,
    String? parentEtag,
    bool? dirty,
    SyncState? syncState,
    double? progress,
    String? conflictOf,
    String? id,
  }) =>
      DotItem(
        id: id ?? this.id,
        type: type,
        title: title ?? this.title,
        body: body ?? this.body,
        fileName: fileName ?? this.fileName,
        fileSize: fileSize ?? this.fileSize,
        mimeType: mimeType ?? this.mimeType,
        sha256: sha256 ?? this.sha256,
        localPath: localPath ?? this.localPath,
        originDeviceId: originDeviceId,
        originName: originName,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        pinned: pinned ?? this.pinned,
        deleted: deleted ?? this.deleted,
        etag: etag ?? this.etag,
        parentEtag: parentEtag ?? this.parentEtag,
        dirty: dirty ?? this.dirty,
        syncState: syncState ?? this.syncState,
        progress: progress ?? this.progress,
        conflictOf: conflictOf ?? this.conflictOf,
      );

  /// Whether this item originated on the device with [deviceId].
  bool isFrom(String deviceId) => originDeviceId == deviceId;

  Map<String, Object?> toDb() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'file_name': fileName,
        'file_size': fileSize,
        'mime_type': mimeType,
        'sha256': sha256,
        'local_path': localPath,
        'origin_device_id': originDeviceId,
        'origin_name': originName,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'pinned': pinned ? 1 : 0,
        'deleted': deleted ? 1 : 0,
        'etag': etag,
        'parent_etag': parentEtag,
        'dirty': dirty ? 1 : 0,
        'sync_state': syncState.name,
        'progress': progress,
        'conflict_of': conflictOf,
      };

  factory DotItem.fromDb(Map<String, Object?> m) => DotItem(
        id: m['id'] as String,
        type: ItemType.values.byName(m['type'] as String),
        title: m['title'] as String,
        body: m['body'] as String,
        fileName: m['file_name'] as String?,
        fileSize: m['file_size'] as int?,
        mimeType: m['mime_type'] as String?,
        sha256: m['sha256'] as String?,
        localPath: m['local_path'] as String?,
        originDeviceId: m['origin_device_id'] as String,
        originName: m['origin_name'] as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(m['created_at'] as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(m['updated_at'] as int),
        pinned: (m['pinned'] as int) == 1,
        deleted: (m['deleted'] as int) == 1,
        etag: m['etag'] as String,
        parentEtag: m['parent_etag'] as String?,
        dirty: (m['dirty'] as int) == 1,
        syncState: SyncState.values.byName(m['sync_state'] as String),
        progress: (m['progress'] as num?)?.toDouble() ?? 0,
        conflictOf: m['conflict_of'] as String?,
      );

  /// Shape sent over the wire. Device-local fields (localPath, dirty,
  /// syncState, progress) are omitted.
  Map<String, Object?> toWire() => {
        'id': id,
        'type': type.name,
        'title': title,
        'body': body,
        'fileName': fileName,
        'fileSize': fileSize,
        'mimeType': mimeType,
        'sha256': sha256,
        'originDeviceId': originDeviceId,
        'originName': originName,
        'createdAt': createdAt.millisecondsSinceEpoch,
        'updatedAt': updatedAt.millisecondsSinceEpoch,
        'pinned': pinned,
        'deleted': deleted,
        'etag': etag,
        'parentEtag': parentEtag,
        'conflictOf': conflictOf,
      };

  /// Unknown item types from newer app versions return null and are skipped.
  static DotItem? fromWire(Map<String, Object?> m) {
    final typeName = m['type'] as String?;
    final type = ItemType.values.where((t) => t.name == typeName).firstOrNull;
    if (type == null) return null;
    return DotItem(
      id: m['id'] as String,
      type: type,
      title: (m['title'] as String?) ?? '',
      body: (m['body'] as String?) ?? '',
      fileName: m['fileName'] as String?,
      fileSize: (m['fileSize'] as num?)?.toInt(),
      mimeType: m['mimeType'] as String?,
      sha256: m['sha256'] as String?,
      originDeviceId: (m['originDeviceId'] as String?) ?? '',
      originName: (m['originName'] as String?) ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch((m['createdAt'] as num).toInt()),
      updatedAt: DateTime.fromMillisecondsSinceEpoch((m['updatedAt'] as num).toInt()),
      pinned: (m['pinned'] as bool?) ?? false,
      deleted: (m['deleted'] as bool?) ?? false,
      etag: m['etag'] as String,
      parentEtag: m['parentEtag'] as String?,
      conflictOf: m['conflictOf'] as String?,
    );
  }

  @override
  String toString() => 'DotItem($id, ${type.name}, etag=$etag, dirty=$dirty, ${syncState.name})';
}

class PairedDevice {
  final String id;
  final String name;
  final DevicePlatform platform;

  /// Base64 Ed25519 public key of the peer.
  final String publicKey;

  /// SHA-256 hex fingerprint of the peer's TLS certificate (only when the
  /// peer is the host / macOS).
  final String? certFingerprint;

  /// Last known address of the host.
  final String? host;
  final int? port;
  final DateTime pairedAt;
  final DateTime? lastConnectedAt;

  const PairedDevice({
    required this.id,
    required this.name,
    required this.platform,
    required this.publicKey,
    this.certFingerprint,
    this.host,
    this.port,
    required this.pairedAt,
    this.lastConnectedAt,
  });

  PairedDevice copyWith({String? name, String? host, int? port, DateTime? lastConnectedAt, String? certFingerprint}) =>
      PairedDevice(
        id: id,
        name: name ?? this.name,
        platform: platform,
        publicKey: publicKey,
        certFingerprint: certFingerprint ?? this.certFingerprint,
        host: host ?? this.host,
        port: port ?? this.port,
        pairedAt: pairedAt,
        lastConnectedAt: lastConnectedAt ?? this.lastConnectedAt,
      );

  Map<String, Object?> toDb() => {
        'id': id,
        'name': name,
        'platform': platform.name,
        'public_key': publicKey,
        'cert_fingerprint': certFingerprint,
        'host': host,
        'port': port,
        'paired_at': pairedAt.millisecondsSinceEpoch,
        'last_connected_at': lastConnectedAt?.millisecondsSinceEpoch,
      };

  factory PairedDevice.fromDb(Map<String, Object?> m) => PairedDevice(
        id: m['id'] as String,
        name: m['name'] as String,
        platform: platformFromString(m['platform'] as String?),
        publicKey: m['public_key'] as String,
        certFingerprint: m['cert_fingerprint'] as String?,
        host: m['host'] as String?,
        port: m['port'] as int?,
        pairedAt: DateTime.fromMillisecondsSinceEpoch(m['paired_at'] as int),
        lastConnectedAt: m['last_connected_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(m['last_connected_at'] as int),
      );
}

/// What the macOS host shows while waiting to be scanned.
class PairingOffer {
  final String qrPayload;

  /// Short code for the manual route.
  final String manualCode;
  final String host;
  final int port;
  final DateTime expiresAt;
  const PairingOffer({
    required this.qrPayload,
    required this.manualCode,
    required this.host,
    required this.port,
    required this.expiresAt,
  });
}

/// What the Android client shows before the user confirms.
class PairingPreview {
  final String host;
  final int port;
  final String token;
  final String? certFingerprint;
  final String peerName;
  final String? peerId;
  const PairingPreview({
    required this.host,
    required this.port,
    required this.token,
    required this.certFingerprint,
    required this.peerName,
    this.peerId,
  });
}

/// Incoming pair request on the host, waiting for the user's confirmation.
class PairingRequest {
  final String requestId;
  final String deviceName;
  final DevicePlatform platform;
  const PairingRequest({required this.requestId, required this.deviceName, required this.platform});
}

sealed class SyncEvent {
  const SyncEvent();
}

class ItemSentEvent extends SyncEvent {
  final String itemId;
  const ItemSentEvent(this.itemId);
}

class ItemReceivedEvent extends SyncEvent {
  final String itemId;
  const ItemReceivedEvent(this.itemId);
}

class PairRequestEvent extends SyncEvent {
  final PairingRequest request;
  const PairRequestEvent(this.request);
}

class PairedEvent extends SyncEvent {
  final PairedDevice device;
  const PairedEvent(this.device);
}

class PairingFailedEvent extends SyncEvent {
  final String message;
  const PairingFailedEvent(this.message);
}

String prettyJson(Object o) => const JsonEncoder.withIndent('  ').convert(o);
