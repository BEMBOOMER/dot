import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:dot/core/database.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/models.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ItemRepository repository;
  final now = DateTime(2026);
  DotItem item({
    String id = 'item',
    String etag = 'remote',
    String? parent,
    ItemType type = ItemType.text,
    bool deleted = false,
    DateTime? updated,
  }) => DotItem(
    id: id,
    type: type,
    title: 'Titel',
    body: 'Inhoud',
    originDeviceId: 'peer',
    originName: 'MacBook',
    createdAt: now,
    updatedAt: updated ?? now,
    etag: etag,
    parentEtag: parent,
    deleted: deleted,
  );
  setUp(() async {
    db = await DotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = ItemRepository(db);
  });
  tearDown(() async {
    repository.dispose();
    await db.close();
  });
  test('inserts remote items and ignores duplicate versions', () async {
    expect(await repository.applyRemote(item()), ApplyResult.inserted);
    expect(await repository.applyRemote(item()), ApplyResult.duplicate);
    expect((await repository.get('item'))!.dirty, isFalse);
    expect((await repository.all()).length, 1);
  });
  test('local tombstone cannot be resurrected', () async {
    await repository.applyRemote(item());
    await repository.delete('item');
    expect(
      await repository.applyRemote(item(etag: 'new')),
      ApplyResult.ignoredTombstone,
    );
    expect(await repository.all(), isEmpty);
    expect((await repository.pending()).single.deleted, isTrue);
  });
  test('remote tombstone wins over a dirty local version', () async {
    await repository.upsertLocal(item());
    expect(
      await repository.applyRemote(item(deleted: true)),
      ApplyResult.updated,
    );
    expect((await repository.get('item'))!.deleted, isTrue);
    expect(await repository.pending(), isEmpty);
  });
  test('matching parent fast-forwards dirty local item', () async {
    final saved = await repository.upsertLocal(item());
    expect(
      await repository.applyRemote(item(etag: 'next', parent: saved.etag)),
      ApplyResult.updated,
    );
    expect((await repository.get('item'))!.etag, 'next');
  });
  test('clean local item fast-forwards despite unrelated parent', () async {
    await repository.applyRemote(item());
    expect(
      await repository.applyRemote(item(etag: 'next')),
      ApplyResult.updated,
    );
  });
  test('note conflict preserves both versions and queues the copy', () async {
    final local = await repository.upsertLocal(item(type: ItemType.note));
    expect(
      await repository.applyRemote(item(type: ItemType.note, etag: 'other')),
      ApplyResult.conflictCopy,
    );
    final items = await repository.all();
    expect(items.length, 2);
    expect((await repository.get('item'))!.etag, local.etag);
    final copy = items.singleWhere((i) => i.id != 'item');
    expect(copy.conflictOf, 'item');
    expect(copy.title, 'Titel (andere versie)');
    expect(copy.dirty, isTrue);
    expect(
      await repository.applyRemote(item(type: ItemType.note, etag: 'other')),
      ApplyResult.duplicate,
    );
    expect((await repository.all()).length, 2);
  });
  test('other conflicts use last writer wins', () async {
    final saved = await repository.upsertLocal(item());
    expect(
      await repository.applyRemote(item(etag: 'older')),
      ApplyResult.keptLocal,
    );
    expect(
      await repository.applyRemote(
        item(
          etag: 'newer',
          updated: saved.updatedAt.add(const Duration(seconds: 1)),
        ),
      ),
      ApplyResult.updated,
    );
    expect((await repository.get('item'))!.etag, 'newer');
  });
  test('ack only clears the matching etag', () async {
    final first = await repository.upsertLocal(item());
    final second = await repository.upsertLocal(
      first.copyWith(body: 'Bewerkt'),
    );
    await repository.markSynced(second.id, first.etag);
    expect((await repository.get(second.id))!.dirty, isTrue);
    await repository.markSynced(second.id, second.etag);
    expect((await repository.get(second.id))!.dirty, isFalse);
    expect((await repository.get(second.id))!.syncState, SyncState.received);
  });
  test('history keeps pinned items and tombstones all other items', () async {
    await repository.upsertLocal(item());
    await repository.upsertLocal(item(id: 'pinned').copyWith(pinned: true));
    await repository.clearHistory();
    expect((await repository.all()).single.id, 'pinned');
    expect((await repository.get('item'))!.deleted, isTrue);
  });
}
