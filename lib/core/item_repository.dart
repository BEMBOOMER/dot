import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import 'models.dart';

const _uuid = Uuid();
String newId() => _uuid.v4();

/// Result of applying a remote item; tells the sync layer what to do next.
enum ApplyResult {
  inserted,
  updated,
  duplicate,
  ignoredTombstone,
  conflictCopy,
  keptLocal,
}

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
    final rows = await db.query(
      'items',
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'pinned DESC, updated_at DESC',
    );
    return rows.map(DotItem.fromDb).toList();
  }

  Future<DotItem?> get(String id) => _get(db, id);

  Future<DotItem?> _get(DatabaseExecutor executor, String id) async {
    final rows = await executor.query(
      'items',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : DotItem.fromDb(rows.first);
  }

  /// Items (including tombstones) that still need to reach the peer.
  Future<List<DotItem>> pending() async {
    final rows = await db.query(
      'items',
      where: 'dirty = 1',
      orderBy: 'updated_at ASC',
    );
    return rows.map(DotItem.fromDb).toList();
  }

  Future<void> _put(DatabaseExecutor executor, DotItem item) async {
    await executor.insert(
      'items',
      item.toDb(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Save a local creation or edit. Gives it a fresh etag and queues it.
  /// [hasPeer] decides whether the state reads "Wacht op verbinding" or
  /// "Lokaal opgeslagen".
  Future<DotItem> upsertLocal(DotItem item, {bool hasPeer = true}) async {
    final saved = await db.transaction((txn) async {
      final existing = await _get(txn, item.id);
      if (existing?.deleted == true && !item.deleted) return existing!;
      final saved = item.copyWith(
        parentEtag: existing?.etag ?? item.parentEtag,
        etag: newId(),
        updatedAt: DateTime.now(),
        dirty: true,
        syncState: hasPeer ? SyncState.waiting : SyncState.local,
        progress: 0,
      );
      await _put(txn, saved);
      return saved;
    });
    notifyListeners();
    return saved;
  }

  /// Tombstone: deleted items never come back, even if the peer resends them.
  Future<void> delete(String id, {bool hasPeer = true}) async {
    final existing = await get(id);
    if (existing == null) return;
    await upsertLocal(
      existing.copyWith(deleted: true, body: '', title: ''),
      hasPeer: hasPeer,
    );
  }

  Future<void> togglePin(String id, {bool hasPeer = true}) async {
    final existing = await get(id);
    if (existing == null) return;
    await upsertLocal(
      existing.copyWith(pinned: !existing.pinned),
      hasPeer: hasPeer,
    );
  }

  /// Apply an item received from the peer. See docs/ARCHITECTURE.md.
  Future<ApplyResult> applyRemote(DotItem incoming) async {
    final result = await db.transaction((txn) => _applyRemote(txn, incoming));
    if (result == ApplyResult.inserted ||
        result == ApplyResult.updated ||
        result == ApplyResult.conflictCopy) {
      notifyListeners();
    }
    return result;
  }

  Future<ApplyResult> _applyRemote(
    DatabaseExecutor txn,
    DotItem incoming,
  ) async {
    final local = await _get(txn, incoming.id);
    final received = incoming.copyWith(
      dirty: false,
      syncState: SyncState.received,
      progress: incoming.type == ItemType.file ? 0 : 1,
    );

    if (local == null) {
      await _put(txn, received);
      return ApplyResult.inserted;
    }
    if (local.deleted) return ApplyResult.ignoredTombstone;
    if (incoming.deleted) {
      await _put(
        txn,
        local.copyWith(
          deleted: true,
          title: '',
          body: '',
          etag: incoming.etag,
          dirty: false,
          syncState: SyncState.received,
        ),
      );
      return ApplyResult.updated;
    }
    if (local.etag == incoming.etag) return ApplyResult.duplicate;
    if (!local.dirty || local.etag == incoming.parentEtag) {
      // Keep device-local file state when only metadata changed.
      final merged = received.copyWith(
        localPath: local.sha256 == incoming.sha256 ? local.localPath : null,
        progress: local.localPath != null && local.sha256 == incoming.sha256
            ? 1
            : received.progress,
      );
      await _put(txn, merged);
      return ApplyResult.updated;
    }

    // Both sides changed the item while apart.
    if (local.type == ItemType.note) {
      final conflictId = _uuid.v5(
        Namespace.url.value,
        'dot:conflict:${local.id}:${incoming.etag}',
      );
      if (await _get(txn, conflictId) != null) return ApplyResult.duplicate;
      final copy = received.copyWith(
        id: conflictId,
        etag: newId(),
        dirty: true,
        syncState: SyncState.waiting,
        conflictOf: local.id,
        title: '${incoming.title} (andere versie)',
      );
      await _put(txn, copy);
      return ApplyResult.conflictCopy;
    }
    if (incoming.updatedAt.isAfter(local.updatedAt)) {
      await _put(
        txn,
        received.copyWith(
          localPath: local.sha256 == incoming.sha256 ? local.localPath : null,
        ),
      );
      return ApplyResult.updated;
    }
    return ApplyResult.keptLocal;
  }

  /// The peer acknowledged [etag]. Only clears dirty if nothing changed since.
  Future<void> markSynced(String id, String etag) async {
    final item = await get(id);
    if (item == null || item.etag != etag) return;
    await db.update(
      'items',
      {'dirty': 0, 'sync_state': SyncState.received.name, 'progress': 1},
      where: 'id = ? AND etag = ?',
      whereArgs: [id, etag],
    );
    notifyListeners();
  }

  Future<void> setSyncState(String id, SyncState state) async {
    await db.update(
      'items',
      {'sync_state': state.name},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  /// Throttle-friendly progress update (callers should not call per byte).
  Future<void> setProgress(String id, double progress) async {
    await db.update(
      'items',
      {'progress': progress},
      where: 'id = ?',
      whereArgs: [id],
    );
    notifyListeners();
  }

  Future<void> setLocalPath(String id, String path) async {
    await db.update(
      'items',
      {'local_path': path, 'progress': 1},
      where: 'id = ?',
      whereArgs: [id],
    );
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
