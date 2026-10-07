import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../core/item_repository.dart';
import '../core/models.dart';
import 'protocol.dart';

class _Incoming {
  final DotItem item;
  final File partial;
  final File target;
  final int size;
  final String hash;
  int offset;
  _Incoming(
    this.item,
    this.partial,
    this.target,
    this.size,
    this.hash,
    this.offset,
  );
}

/// Acknowledging each chunk with file_resume bounds memory to one chunk and
/// leaves a durable resume offset when a transport disappears.
class FileTransfer {
  final ItemRepository repository;
  final Future<Directory> Function() downloadDirectory;
  final void Function(String, Map<String, Object?>) send;
  final void Function(Uint8List) sendBinary;
  final void Function(String) onSent;
  final void Function(String) onReceived;
  final void Function(String) onFinished;
  final ValueNotifier<Map<String, double>> progress = ValueNotifier({});
  final Map<String, DotItem> _outgoing = {};
  final Map<String, _Incoming> _incoming = {};
  final Map<String, DateTime> _lastProgress = {};
  final Map<String, int> _lastSentOffset = {};
  FileTransfer({
    required this.repository,
    required this.downloadDirectory,
    required this.send,
    required this.sendBinary,
    required this.onSent,
    required this.onReceived,
    required this.onFinished,
  });

  bool get busy => _outgoing.isNotEmpty || _incoming.isNotEmpty;
  Future<bool> offer(DotItem item) async {
    if (_outgoing.containsKey(item.id)) return true;
    if (item.localPath == null ||
        !await File(item.localPath!).exists() ||
        item.sha256 == null) {
      await repository.setSyncState(item.id, SyncState.failed);
      onFinished(item.id);
      return false;
    }
    _outgoing[item.id] = item;
    await repository.setSyncState(item.id, SyncState.sending);
    send('file_offer', {
      'id': item.id,
      'etag': item.etag,
      'name': item.fileName,
      'size': item.fileSize,
      'sha256': item.sha256,
      'offset': 0,
    });
    return true;
  }

  Future<void> receiveOffer(Map<String, dynamic> message) async {
    final id = message['id'] as String;
    final item = await repository.get(id);
    if (item == null || item.deleted || item.etag != message['etag']) {
      send('file_ack', {
        'id': id,
        'etag': message['etag'],
        'ok': item?.deleted == true,
      });
      return;
    }
    final size = message['size'] as int;
    final hash = message['sha256'] as String;
    if (size < 0 ||
        size != item.fileSize ||
        hash != item.sha256 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash)) {
      throw const FormatException('Ongeldige bestandsgegevens.');
    }
    if (item.localPath != null && await File(item.localPath!).exists()) {
      final existing = File(item.localPath!);
      if (await existing.length() == size &&
          (await sha256.bind(existing.openRead()).first).toString() == hash) {
        send('file_ack', {'id': id, 'etag': item.etag, 'ok': true});
        return;
      }
    }
    final directory = await downloadDirectory();
    await directory.create(recursive: true);
    if (!RegExp(r'^[a-fA-F0-9-]{36}$').hasMatch(id)) {
      throw const FormatException('Ongeldig bestands-ID.');
    }
    // ID prefix prevents collisions. Basename and control-character removal
    // prevent peer-controlled paths escaping the configured directory.
    var name = p
        .basename(message['name'] as String? ?? 'bestand')
        .replaceAll(RegExp(r'[\x00-\x1f\\/]'), '_');
    if (name.isEmpty || name == '.' || name == '..') name = 'bestand';
    if (name.length > 150) name = name.substring(0, 150);
    final target = File(p.join(directory.path, '${id}_$name'));
    final partial = File('${target.path}.$hash.part');
    if (!await partial.exists()) await partial.writeAsBytes([]);
    var offset = await partial.length();
    if (offset > size) {
      await partial.writeAsBytes([]);
      offset = 0;
    }
    _incoming[id] = _Incoming(item, partial, target, size, hash, offset);
    await repository.setSyncState(id, SyncState.sending);
    await _update(id, size == 0 ? 0 : offset / size, force: true);
    send('file_resume', {'id': id, 'offset': offset});
  }

  Future<void> resume(Map<String, dynamic> message) async {
    final id = message['id'] as String;
    final item = _outgoing[id];
    if (item == null) return;
    final offset = message['offset'] as int;
    final size = item.fileSize!;
    if (offset < 0 || offset > size) {
      throw const FormatException('Ongeldige hervatpositie.');
    }
    if (_lastSentOffset[id] == offset) return;
    _lastSentOffset[id] = offset;
    await _update(id, size == 0 ? 1 : offset / size);
    if (offset == size) {
      send('file_done', {'id': id, 'sha256': item.sha256});
      return;
    }
    final file = await File(item.localPath!).open();
    try {
      await file.setPosition(offset);
      final bytes = await file.read((size - offset).clamp(0, chunkSize));
      if (bytes.isEmpty) {
        throw const FileSystemException('Bestand is gewijzigd.');
      }
      if (_outgoing[id] != item) return;
      sendBinary(FileChunk(id, offset, bytes).encode());
    } finally {
      await file.close();
    }
  }

  Future<void> receiveChunk(List<int> bytes) async {
    final chunk = FileChunk.decode(bytes);
    final transfer = _incoming[chunk.id];
    if (transfer == null) return;
    if (chunk.offset != transfer.offset ||
        chunk.offset + chunk.bytes.length > transfer.size ||
        chunk.bytes.isEmpty) {
      throw const FormatException('Ongeldige bestandsvolgorde.');
    }
    final file = await transfer.partial.open(mode: FileMode.append);
    try {
      await file.writeFrom(chunk.bytes);
      await file.flush();
    } finally {
      await file.close();
    }
    transfer.offset += chunk.bytes.length;
    await _update(
      chunk.id,
      transfer.size == 0 ? 1 : transfer.offset / transfer.size,
    );
    send('file_resume', {'id': chunk.id, 'offset': transfer.offset});
  }

  Future<void> done(Map<String, dynamic> message) async {
    final id = message['id'] as String;
    final transfer = _incoming.remove(id);
    if (transfer == null) return;
    final hash = (await sha256.bind(transfer.partial.openRead()).first)
        .toString();
    final current = await repository.get(id);
    final ok =
        current != null &&
        !current.deleted &&
        current.etag == transfer.item.etag &&
        transfer.offset == transfer.size &&
        hash == transfer.hash &&
        hash == message['sha256'];
    if (ok) {
      await transfer.partial.rename(transfer.target.path);
      await repository.setLocalPath(id, transfer.target.path);
      await repository.setSyncState(id, SyncState.received);
      await _update(id, 1, force: true);
      onReceived(id);
    } else {
      // A corrupt prefix must not be reused on retry.
      await transfer.partial.delete();
      await repository.setSyncState(id, SyncState.failed);
    }
    send('file_ack', {'id': id, 'etag': transfer.item.etag, 'ok': ok});
    _clear(id);
  }

  Future<void> acknowledge(Map<String, dynamic> message) async {
    final id = message['id'] as String;
    final item = _outgoing[id];
    if (item == null ||
        (message['etag'] != null && message['etag'] != item.etag)) {
      return;
    }
    _outgoing.remove(id);
    if (message['ok'] == true) {
      await repository.markSynced(id, item.etag);
      onSent(id);
    } else {
      await repository.setSyncState(id, SyncState.failed);
    }
    _clear(id);
    onFinished(id);
  }

  Future<void> cancel(String id, {bool notifyPeer = true}) async {
    _outgoing.remove(id);
    _incoming.remove(id);
    if (notifyPeer) send('file_cancel', {'id': id});
    await repository.setSyncState(id, SyncState.failed);
    _clear(id);
    onFinished(id);
  }

  Future<void> disconnected() async {
    final ids = {..._outgoing.keys, ..._incoming.keys};
    _outgoing.clear();
    _incoming.clear();
    _lastSentOffset.clear();
    for (final id in ids) {
      await repository.setSyncState(id, SyncState.waiting);
    }
    progress.value = {};
  }

  Future<void> _update(String id, double value, {bool force = false}) async {
    final now = DateTime.now();
    if (!force &&
        _lastProgress[id] != null &&
        now.difference(_lastProgress[id]!).inMilliseconds < 100) {
      return;
    }
    _lastProgress[id] = now;
    progress.value = {...progress.value, id: value};
    await repository.setProgress(id, value);
  }

  void _clear(String id) {
    _lastSentOffset.remove(id);
    _lastProgress.remove(id);
    progress.value = Map.of(progress.value)..remove(id);
  }

  void dispose() => progress.dispose();
}
