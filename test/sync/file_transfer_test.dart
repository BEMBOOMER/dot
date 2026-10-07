import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dot/core/database.dart';
import 'package:dot/core/item_repository.dart';
import 'package:dot/core/models.dart';
import 'package:dot/sync/file_transfer.dart';
import 'package:dot/sync/protocol.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  late Database db;
  late ItemRepository repository;
  late Directory directory;
  late FileTransfer receiver;
  late List<Map<String, Object?>> replies;
  setUp(() async {
    db = await DotDatabase.open(
      factory: databaseFactoryFfi,
      path: inMemoryDatabasePath,
    );
    repository = ItemRepository(db);
    directory = await Directory.systemTemp.createTemp('dot-resume-');
    replies = [];
    receiver = FileTransfer(
      repository: repository,
      downloadDirectory: () async => directory,
      send: (type, fields) => replies.add({'t': type, ...fields}),
      sendBinary: (_) {},
      onSent: (_) {},
      onReceived: (_) {},
      onFinished: (_) {},
    );
  });
  tearDown(() async {
    await receiver.disconnected();
    receiver.dispose();
    repository.dispose();
    await db.close();
    await directory.delete(recursive: true);
  });

  Future<DotItem> incoming(Uint8List bytes) async {
    final now = DateTime.now();
    final item = DotItem(
      id: newId(),
      type: ItemType.file,
      title: 'Bestand',
      body: '',
      fileName: '../../sample.bin',
      fileSize: bytes.length,
      sha256: sha256.convert(bytes).toString(),
      originDeviceId: 'peer',
      originName: 'MacBook',
      createdAt: now,
      updatedAt: now,
      etag: newId(),
    );
    await repository.applyRemote(item);
    return item;
  }

  Map<String, dynamic> offer(DotItem item) => {
    'id': item.id,
    'etag': item.etag,
    'name': item.fileName,
    'size': item.fileSize,
    'sha256': item.sha256,
  };

  test('cancel retains the durable prefix and retry resumes at the receiver offset', () async {
    final bytes = Uint8List.fromList(
      List.generate(chunkSize * 4, (i) => i % 251),
    );
    final item = await incoming(bytes);
    await receiver.receiveOffer(offer(item));
    expect(replies.last['offset'], 0);
    await receiver.receiveChunk(
      FileChunk(
        item.id,
        0,
        Uint8List.sublistView(bytes, 0, chunkSize),
      ).encode(),
    );
    expect(replies.last['offset'], chunkSize);
    await receiver.cancel(item.id);
    expect(replies.last['t'], 'file_cancel');
    expect((await repository.get(item.id))!.localPath, isNull);
    expect((await repository.get(item.id))!.syncState, SyncState.failed);
    await receiver.receiveOffer(offer(item));
    expect(replies.last['offset'], chunkSize);
    for (var offset = chunkSize; offset < bytes.length; offset += chunkSize) {
      await receiver.receiveChunk(
        FileChunk(
          item.id,
          offset,
          Uint8List.sublistView(bytes, offset, offset + chunkSize),
        ).encode(),
      );
    }
    await receiver.done({'id': item.id, 'sha256': item.sha256});
    expect(replies.last['t'], 'file_ack');
    expect(replies.last['ok'], isTrue);
    final saved = (await repository.get(item.id))!;
    expect(File(saved.localPath!).parent.path, directory.path);
    expect(await File(saved.localPath!).readAsBytes(), bytes);
    expect(saved.syncState, SyncState.received);
    expect(
      await directory.list().where((e) => e.path.endsWith('.part')).isEmpty,
      isTrue,
    );
  });

  test(
    'checksum failure discards corrupt prefix and never acknowledges success',
    () async {
      final bytes = Uint8List.fromList([1, 2, 3]);
      final item = await incoming(bytes);
      await receiver.receiveOffer(offer(item));
      await receiver.receiveChunk(
        FileChunk(item.id, 0, Uint8List.fromList([3, 2, 1])).encode(),
      );
      await receiver.done({'id': item.id, 'sha256': item.sha256});
      expect(replies.last['ok'], isFalse);
      expect((await repository.get(item.id))!.localPath, isNull);
      expect((await repository.get(item.id))!.syncState, SyncState.failed);
      await receiver.receiveOffer(offer(item));
      expect(replies.last['offset'], 0);
    },
  );

  test('incorrect offsets are rejected before appending data', () async {
    final item = await incoming(Uint8List(100));
    await receiver.receiveOffer(offer(item));
    await expectLater(
      receiver.receiveChunk(FileChunk(item.id, 10, Uint8List(20)).encode()),
      throwsFormatException,
    );
    expect((await directory.list().toList()).single.statSync().size, 0);
  });

  test('sender stays dirty until file_ack ok', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    final remote = await incoming(bytes);
    final source = File('${directory.path}/source.bin');
    await source.writeAsBytes(bytes);
    final item = await repository.upsertLocal(
      remote.copyWith(localPath: source.path),
    );
    await receiver.offer(item);
    expect((await repository.get(item.id))!.dirty, isTrue);
    expect((await repository.get(item.id))!.syncState, SyncState.sending);
    await receiver.acknowledge({'id': item.id, 'etag': item.etag, 'ok': false});
    expect((await repository.get(item.id))!.dirty, isTrue);
    expect((await repository.get(item.id))!.syncState, SyncState.failed);
    await receiver.offer(item);
    await receiver.acknowledge({'id': item.id, 'etag': item.etag, 'ok': true});
    expect((await repository.get(item.id))!.dirty, isFalse);
    expect((await repository.get(item.id))!.syncState, SyncState.received);
  });
}
