import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Result of applying a remote item; tells the sync layer what to do next.
enum ApplyResult { inserted, updated, duplicate, ignoredTombstone, conflictCopy, keptLocal }

class ItemRepository extends ChangeNotifier {
  final Database db;
  ItemRepository(this.db);

  /// Visible items: not deleted, pinned first, newest first.
  Future<List<DotItem>> all({String? query, ItemType? type}) async {
    final where = <String>['deleted = 0'];
    final args = <Object?>[];
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    if (query != null && query.trim().isNotEmpty) {
      where.add('(title LIKE ? OR body LIKE ? OR file_name LIKE ?)');
      final q = '%${query.trim()}%';
      args.addAll([q, q, q]);
    }
    final rows = await db.query('items',
        where: where.join(' AND '), whereArgs: args, orderBy: 'pinned DESC, updated_at DESC');
    return rows.map(DotItem.fromDb).toList();
  }

  Future<DotItem?> get(String id) async {
    final rows = await db.query('items', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : DotItem.fromDb(rows.first);
  }

  /// Items (including tombstones) that still need to reach the peer.
  Future<List<DotItem>> pending() async {
    final rows = await db.query('items', where: 'dirty = 1', orderBy: 'updated_at ASC');
    return rows.map(DotItem.fromDb).toList();
  }

  Future<void> _put(DotItem item) async {
    await db.insert('items', item.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// Save a local creation or edit. Gives it a fresh etag and queues it.
  /// [hasPeer] decides whether the state reads "Wacht op verbinding" or
  /// "Lokaal opgeslagen".
  Future<DotItem> upsertLocal(DotItem item, {bool hasPeer = true}) async {
    final existing = await get(item.id);
    final saved = item.copyWith(
      parentEtag: existing?.etag ?? item.parentEtag,
      etag: newId(),
      updatedAt: DateTime.now(),
      dirty: true,
      syncState: hasPeer ? SyncState.waiting : SyncState.local,
      progress: 0,
    );
    await _put(saved);
    notifyListeners();
    return saved;
  }

  /// Tombstone: deleted items never come back, even if the peer resends them.
  Future<void> delete(String id, {bool hasPeer = true}) async {
    final existing = await get(id);
    if (existing == null) return;
    await upsertLocal(existing.copyWith(deleted: true, body: '', title: ''), hasPeer: hasPeer);
  }

  Future<void> togglePin(String id, {bool hasPeer = true}) async {
    final existing = await get(id);
    if (existing == null) return;
    await upsertLocal(existing.copyWith(pinned: !existing.pinned), hasPeer: hasPeer);
  }

  /// Apply an item received from the peer. See docs/ARCHITECTURE.md.
  Future<ApplyResult> applyRemote(DotItem incoming) async {
    final local = await get(incoming.id);
    final received = incoming.copyWith(dirty: false, syncState: SyncState.received, progress: incoming.type == ItemType.file ? 0 : 1);

    if (local == null) {
      await _put(received);
      notifyListeners();
      return ApplyResult.inserted;
    }
    if (local.deleted) return ApplyResult.ignoredTombstone;
    if (local.etag == incoming.etag) return ApplyResult.duplicate;
    if (incoming.deleted) {
      await _put(local.copyWith(deleted: true, title: '', body: '', etag: incoming.etag, dirty: false, syncState: SyncState.received));
      notifyListeners();
      return ApplyResult.updated;
    }
    if (!local.dirty || local.etag == incoming.parentEtag) {
      // Keep device-local file state when only metadata changed.
      final merged = received.copyWith(
        localPath: local.localPath,
        progress: local.localPath != null ? 1 : received.progress,
      );
      await _put(merged);
      notifyListeners();
      return ApplyResult.updated;
    }

    // Both sides changed the item while apart.
    if (local.type == ItemType.note) {
      final copy = received.copyWith(
        id: newId(),
        etag: newId(),
        conflictOf: local.id,
        title: '${incoming.title} (andere versie)',
      );
      await _put(copy);
      notifyListeners();
      return ApplyResult.conflictCopy;
    }
    if (incoming.updatedAt.isAfter(local.updatedAt)) {
      await _put(received.copyWith(localPath: local.localPath));
      notifyListeners();
      return ApplyResult.updated;
    }
    return ApplyResult.keptLocal;
  }

  /// The peer acknowledged [etag]. Only clears dirty if nothing changed since.
  Future<void> markSynced(String id, String etag) async {
    final item = await get(id);
    if (item == null || item.etag != etag) return;
    await _put(item.copyWith(dirty: false, syncState: SyncState.received, progress: 1));
    notifyListeners();
  }

  Future<void> setSyncState(String id, SyncState state) async {
    await db.update('items', {'sync_state': state.name}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  /// Throttle-friendly progress update (callers should not call per byte).
  Future<void> setProgress(String id, double progress) async {
    await db.update('items', {'progress': progress}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  Future<void> setLocalPath(String id, String path) async {
    await db.update('items', {'local_path': path, 'progress': 1}, where: 'id = ?', whereArgs: [id]);
    notifyListeners();
  }

  /// Marks every waiting/local item with the given state, e.g. when a peer
  /// becomes available or the pairing is removed.
  Future<void> setStateForDirty(SyncState state) async {
    await db.update('items', {'sync_state': state.name}, where: 'dirty = 1');
    notifyListeners();
  }

  /// Removes unpinned history. Tombstones are kept so deleted items stay
  /// deleted on the peer; content is wiped.
  Future<void> clearHistory({bool hasPeer = true}) async {
    final rows = await db.query('items', where: 'deleted = 0 AND pinned = 0');
    for (final r in rows) {
      await delete(r['id'] as String, hasPeer: hasPeer);
    }
  }
}
