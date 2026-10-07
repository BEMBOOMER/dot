import 'package:dot/core/database.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ItemRepository repository;

  final baseTime = DateTime(2026, 1, 1);

  DotItem item({
    String id = 'item',
    ItemType type = ItemType.text,
    String etag = 'etag',
    String? parentEtag,
    String body = 'Inhoud',
    DateTime? updatedAt,
    bool pinned = false,
  }) =>
      DotItem(
        id: id,
        type: type,
        title: 'Titel',
        body: body,
        originDeviceId: 'peer',
        originName: 'MacBook',
        createdAt: baseTime,
        updatedAt: updatedAt ?? baseTime,
        etag: etag,
        parentEtag: parentEtag,
        pinned: pinned,
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

  test('a tombstone survives a later resend of an older etag', () async {
    await repository.applyRemote(item(etag: 'old'));
    await repository.delete('item');

    expect(
      await repository.applyRemote(item(etag: 'older')),
      ApplyResult.ignoredTombstone,
    );
    expect(await repository.get('item'), isNotNull);
    expect((await repository.get('item'))!.deleted, isTrue);
    expect((await repository.pending()).single.deleted, isTrue);
  });

  test('clearHistory keeps pinned items and queues tombstones for the rest',
      () async {
    final ordinary = await repository.upsertLocal(item(id: 'ordinary'));
    final pinned = await repository.upsertLocal(
      item(id: 'pinned', pinned: true),
    );
    await repository.markSynced(ordinary.id, ordinary.etag);
    await repository.markSynced(pinned.id, pinned.etag);

    await repository.clearHistory();

    expect((await repository.all()).map((i) => i.id), ['pinned']);
    final pending = await repository.pending();
    expect(pending.map((i) => i.id), ['ordinary']);
    expect(pending.single.deleted, isTrue);
  });

  test('pending includes dirty tombstones', () async {
    await repository.upsertLocal(item());
    await repository.delete('item');

    final pending = await repository.pending();
    expect(pending, hasLength(1));
    expect(pending.single.deleted, isTrue);
    expect(pending.single.dirty, isTrue);
  });

  test('markSynced with a stale etag keeps the current item dirty', () async {
    final first = await repository.upsertLocal(item());
    final second = await repository.upsertLocal(
      first.copyWith(body: 'Nieuwe inhoud'),
    );

    await repository.markSynced(second.id, first.etag);

    final current = await repository.get(second.id);
    expect(current!.etag, second.etag);
    expect(current.dirty, isTrue);
  });

  test('link conflict uses last writer wins by updatedAt', () async {
    final local = await repository.upsertLocal(item(type: ItemType.link));
    final newer = item(
      type: ItemType.link,
      etag: 'newer',
      body: 'https://example.com/new',
      updatedAt: local.updatedAt.add(const Duration(seconds: 1)),
    );

    expect(await repository.applyRemote(newer), ApplyResult.updated);
    expect((await repository.get(local.id))!.body, newer.body);
    expect((await repository.get(local.id))!.etag, newer.etag);
  });

  test('unknown wire item types are skipped', () {
    final wire = <String, Object?>{
      'id': 'item',
      'type': 'future_type',
      'title': 'Titel',
      'body': 'Inhoud',
      'createdAt': baseTime.millisecondsSinceEpoch,
      'updatedAt': baseTime.millisecondsSinceEpoch,
      'etag': 'etag',
    };

    expect(DotItem.fromWire(wire), isNull);
  });
}
