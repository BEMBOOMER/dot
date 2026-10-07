import 'dart:io';

import 'package:dot/core/database.dart';
import 'package:dot/platform/mac_migration.dart';
import 'package:dot/sync/identity.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  sqfliteFfiInit();
  late Directory root;
  late MacDataMigration migration;
  Future<File> write(String path, String value) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    return file.writeAsString(value);
  }

  setUp(() async {
    root = await Directory.systemTemp.createTemp('dot-migration-');
    final support = Directory(
      p.join(root.path, 'Library', 'Application Support', 'com.bemooks.dot'),
    );
    migration = MacDataMigration(
      oldSupport: Directory(
        p.join(
          root.path,
          'container',
          'Library',
          'Application Support',
          'com.bemooks.dot',
        ),
      ),
      newSupport: support,
      oldDatabases: Directory(p.join(root.path, 'container', 'Documents')),
      newDatabases: support,
      documentsDirectory: Directory(p.join(root.path, 'Documents')),
      oldPreferences: File(
        p.join(
          root.path,
          'container',
          'Library',
          'Preferences',
          'com.bemooks.dot.plist',
        ),
      ),
      newPreferences: File(
        p.join(root.path, 'Library', 'Preferences', 'com.bemooks.dot.plist'),
      ),
    );
  });
  tearDown(() async => root.delete(recursive: true));

  test('macOS opens the default database in Application Support', () async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'getApplicationSupportDirectory');
      return migration.newSupport.path;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final db = await DotDatabase.open(factory: databaseFactoryFfi);
    try {
      expect(db.path, p.join(migration.newSupport.path, 'dot.db'));
      expect(await File(db.path).exists(), isTrue);
      expect(await migration.documentsDirectory!.exists(), isFalse);
    } finally {
      await db.close();
    }
  }, skip: !Platform.isMacOS);

  test('copies container data to Application Support without moving', () async {
    final oldStore = SecureSecretStore(migration.oldSupport);
    final identity = await DeviceIdentity.load(oldStore);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      await write(
        p.join(migration.oldDatabases.path, 'dot.db$suffix'),
        'db$suffix',
      );
    }
    await write(
      p.join(migration.oldSupport.path, 'files', 'nested', 'example.txt'),
      'file',
    );
    await write(migration.oldPreferences.path, 'preferences');
    await migration.copy();
    final restored = await DeviceIdentity.load(
      SecureSecretStore(migration.newSupport),
    );
    expect(restored.deviceId, identity.deviceId);
    expect(restored.publicKey, identity.publicKey);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      expect(
        await File(p.join(migration.newDatabases.path, 'dot.db$suffix'))
            .readAsString(),
        'db$suffix',
      );
      expect(
        await File(p.join(migration.oldDatabases.path, 'dot.db$suffix'))
            .readAsString(),
        'db$suffix',
      );
    }
    expect(
      await File(
        p.join(migration.newSupport.path, 'files', 'nested', 'example.txt'),
      ).readAsString(),
      'file',
    );
    expect(
      await File(
        p.join(migration.oldSupport.path, 'files', 'nested', 'example.txt'),
      ).readAsString(),
      'file',
    );
    expect(await migration.newPreferences.readAsString(), 'preferences');
    expect(await migration.oldPreferences.readAsString(), 'preferences');
    if (!Platform.isWindows) {
      final secret = File(
        p.join(migration.newSupport.path, 'secrets', 'identity.json'),
      );
      expect((await secret.stat()).mode & 0x1ff, 0x180);
      expect((await secret.parent.stat()).mode & 0x1ff, 0x1c0);
    }
    await write(migration.newPreferences.path, 'new preferences');
    await write(p.join(migration.oldDatabases.path, 'dot.db'), 'stale db');
    await migration.copy();
    expect(
      await File(p.join(migration.newDatabases.path, 'dot.db')).readAsString(),
      'db',
    );
    expect(await migration.newPreferences.readAsString(), 'new preferences');
  }, skip: !Platform.isMacOS);

  test('moves the Documents database family to Application Support without a container', () async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      await write(
        p.join(migration.documentsDirectory!.path, 'dot.db$suffix'),
        'documents$suffix',
      );
    }
    await migration.copy();
    expect(await Directory(p.join(root.path, 'container')).exists(), isFalse);
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      expect(
        await File(p.join(migration.newSupport.path, 'dot.db$suffix'))
            .readAsString(),
        'documents$suffix',
      );
      expect(
        await File(p.join(migration.documentsDirectory!.path, 'dot.db$suffix'))
            .exists(),
        isFalse,
      );
    }
    expect(
      await File(p.join(migration.newSupport.path, '.documents-migration'))
          .exists(),
      isFalse,
    );
    await migration.copy();
    expect(
      await File(p.join(migration.newSupport.path, 'dot.db')).readAsString(),
      'documents',
    );
  });

  test('Documents takes precedence over the container and keeps the current identity', () async {
    await write(
      p.join(migration.oldDatabases.path, 'dot.db'),
      'stale database',
    );
    await write(
      p.join(migration.oldSupport.path, 'secrets', 'identity.json'),
      'stale identity',
    );
    await write(
      p.join(migration.documentsDirectory!.path, 'dot.db'),
      'current database',
    );
    final identity = File(
      p.join(migration.newSupport.path, 'secrets', 'identity.json'),
    );
    await write(identity.path, 'current identity');
    await migration.copy();
    expect(
      await File(p.join(migration.newSupport.path, 'dot.db')).readAsString(),
      'current database',
    );
    expect(await identity.readAsString(), 'current identity');
    expect(
      await File(p.join(migration.documentsDirectory!.path, 'dot.db')).exists(),
      isFalse,
    );
    expect(
      await File(p.join(migration.oldDatabases.path, 'dot.db')).readAsString(),
      'stale database',
    );
  });

  for (final fromDocuments in [false, true]) {
    test(
      '${fromDocuments ? 'moves Documents' : 'copies container'} SQLite data including uncheckpointed WAL and pairing rows',
      () async {
        final sourceDatabases = fromDocuments
            ? migration.documentsDirectory!
            : migration.oldDatabases;
        await sourceDatabases.create(recursive: true);
        final old = await DotDatabase.open(
          factory: databaseFactoryFfi,
          path: p.join(sourceDatabases.path, 'dot.db'),
        );
        Database? restored;
        try {
          await old.rawQuery('PRAGMA journal_mode=WAL');
          await old.rawQuery('PRAGMA wal_autocheckpoint=0');
          await old.insert('devices', {
            'id': 'paired-phone',
            'name': 'Android',
            'platform': 'android',
            'public_key': 'saved-public-key',
            'paired_at': 123,
          });
          expect(
            await File(p.join(sourceDatabases.path, 'dot.db-wal')).length(),
            greaterThan(0),
          );
          await migration.copy();
          restored = await DotDatabase.open(
            factory: databaseFactoryFfi,
            path: p.join(migration.newDatabases.path, 'dot.db'),
          );
          expect(
            (await restored.query('devices')).single['id'],
            'paired-phone',
          );
          expect(
            (await restored.rawQuery('PRAGMA integrity_check'))
                .single
                .values
                .single,
            'ok',
          );
          expect(
            await File(p.join(sourceDatabases.path, 'dot.db')).exists(),
            !fromDocuments,
          );
        } finally {
          await restored?.close();
          await old.close();
        }
      },
    );
  }

  for (final cleaningUp in [false, true]) {
    test(
      'resumes an interrupted Documents ${cleaningUp ? 'cleanup' : 'copy'}',
      () async {
        for (final suffix in ['', '-wal', '-shm']) {
          await write(
            p.join(migration.documentsDirectory!.path, 'dot.db$suffix'),
            'documents$suffix',
          );
          if (cleaningUp || suffix == '-wal') {
            await write(
              p.join(migration.newSupport.path, 'dot.db$suffix'),
              'documents$suffix',
            );
          }
        }
        if (cleaningUp) {
          await File(p.join(migration.documentsDirectory!.path, 'dot.db-wal'))
              .delete();
        }
        final marker = await write(
          p.join(migration.newSupport.path, '.documents-migration'),
          'moving',
        );
        await migration.copy();
        for (final suffix in ['', '-wal', '-shm']) {
          expect(
            await File(p.join(migration.newSupport.path, 'dot.db$suffix'))
                .readAsString(),
            'documents$suffix',
          );
          expect(
            await File(
              p.join(migration.documentsDirectory!.path, 'dot.db$suffix'),
            ).exists(),
            isFalse,
          );
        }
        expect(await marker.exists(), isFalse);
      },
    );
  }

  test('does not merge Documents with existing destination sidecars', () async {
    final source = await write(
      p.join(migration.documentsDirectory!.path, 'dot.db'),
      'documents',
    );
    final sidecar = await write(
      p.join(migration.newSupport.path, 'dot.db-wal'),
      'existing WAL',
    );
    await expectLater(migration.copy(), throwsA(isA<FileSystemException>()));
    expect(await source.readAsString(), 'documents');
    expect(await sidecar.readAsString(), 'existing WAL');
    expect(
      await File(p.join(migration.newSupport.path, 'dot.db')).exists(),
      isFalse,
    );
  });

  test(
    'does not merge an old database into an existing new identity',
    () async {
      await write(
        p.join(migration.oldDatabases.path, 'dot.db'),
        'old database',
      );
      await write(
        p.join(migration.newSupport.path, 'secrets', 'identity.json'),
        'new identity',
      );
      await write(migration.oldPreferences.path, 'old settings');
      await write(migration.newPreferences.path, 'new settings');
      await migration.copy();
      expect(
        await File(p.join(migration.newDatabases.path, 'dot.db')).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(migration.newSupport.path, 'secrets', 'identity.json'),
        ).readAsString(),
        'new identity',
      );
      expect(await migration.newPreferences.readAsString(), 'new settings');
    },
  );

  test(
    'existing database is authoritative even when secrets are absent',
    () async {
      await write(
        p.join(migration.oldSupport.path, 'secrets', 'identity.json'),
        'stale identity',
      );
      await write(p.join(migration.oldDatabases.path, 'dot.db'), 'old db');
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        await write(
          p.join(migration.newSupport.path, 'dot.db$suffix'),
          'new db$suffix',
        );
        await write(
          p.join(migration.documentsDirectory!.path, 'dot.db$suffix'),
          'documents$suffix',
        );
      }
      await migration.copy();
      expect(
        await File(
          p.join(migration.newSupport.path, 'secrets', 'identity.json'),
        ).exists(),
        isFalse,
      );
      for (final suffix in ['', '-wal', '-shm', '-journal']) {
        expect(
          await File(p.join(migration.newSupport.path, 'dot.db$suffix'))
              .readAsString(),
          'new db$suffix',
        );
        expect(
          await File(
            p.join(migration.documentsDirectory!.path, 'dot.db$suffix'),
          ).readAsString(),
          'documents$suffix',
        );
      }
    },
  );

  test(
    'failure rolls back this attempt and leaves originals usable for retry',
    () async {
      await write(
        p.join(migration.oldSupport.path, 'secrets', 'identity.json'),
        'identity',
      );
      await write(p.join(migration.oldDatabases.path, 'dot.db'), 'database');
      // A conflicting file prevents creation of the target database directory.
      await write(migration.newDatabases.path, 'blocking file');
      await expectLater(migration.copy(), throwsA(isA<FileSystemException>()));
      expect(
        await Directory(p.join(migration.newSupport.path, 'secrets')).exists(),
        isFalse,
      );
      expect(
        await File(
          p.join(migration.oldSupport.path, 'secrets', 'identity.json'),
        ).readAsString(),
        'identity',
      );
      expect(
        await File(p.join(migration.oldDatabases.path, 'dot.db'))
            .readAsString(),
        'database',
      );
      await File(migration.newDatabases.path).delete();
      await migration.copy();
      expect(
        await File(p.join(migration.newDatabases.path, 'dot.db'))
            .readAsString(),
        'database',
      );
    },
  );

  test(
    'missing legacy data is a no-op; support database layout is also accepted',
    () async {
      await migration.copy();
      expect(await migration.newSupport.exists(), isFalse);
      await write(p.join(migration.oldSupport.path, 'dot.db'), 'support db');
      await migration.copy();
      expect(
        await File(p.join(migration.newDatabases.path, 'dot.db'))
            .readAsString(),
        'support db',
      );
    },
  );

  test(
    'an interrupted migration resumes instead of skipping the paired database',
    () async {
      await write(
        p.join(migration.oldDatabases.path, 'dot.db'),
        'paired database',
      );
      await write(
        p.join(migration.oldSupport.path, 'secrets', 'identity.json'),
        'original identity',
      );
      await write(
        p.join(migration.newSupport.path, 'secrets', 'identity.json'),
        'original identity',
      );
      final marker = await write(
        p.join(migration.newSupport.path, '.sandbox-migration'),
        'copying',
      );
      await migration.copy();
      expect(
        await File(p.join(migration.newDatabases.path, 'dot.db'))
            .readAsString(),
        'paired database',
      );
      expect(await marker.exists(), isFalse);
    },
  );

  for (final fromDocuments in [false, true]) {
    test(
      '${fromDocuments ? 'Documents' : 'container'} preference activation failure retains sources for retry',
      () async {
        final sourceDatabases = fromDocuments
            ? migration.documentsDirectory!
            : migration.oldDatabases;
        await write(p.join(sourceDatabases.path, 'dot.db'), 'database');
        if (fromDocuments) {
          await write(p.join(sourceDatabases.path, 'dot.db-wal'), 'WAL');
        }
        await write(migration.oldPreferences.path, 'preferences');
        var failActivation = true;
        final withActivation = MacDataMigration(
          oldSupport: migration.oldSupport,
          newSupport: migration.newSupport,
          oldDatabases: migration.oldDatabases,
          newDatabases: migration.newDatabases,
          documentsDirectory: migration.documentsDirectory,
          oldPreferences: migration.oldPreferences,
          newPreferences: migration.newPreferences,
          activatePreferences: () async {
            expect(
              await migration.newPreferences.readAsString(),
              'preferences',
            );
            if (failActivation) throw StateError('Preferences reload failed');
          },
        );
        await expectLater(withActivation.copy(), throwsStateError);
        expect(await migration.newPreferences.exists(), isFalse);
        expect(
          await File(p.join(migration.newDatabases.path, 'dot.db')).exists(),
          isFalse,
        );
        expect(await migration.oldPreferences.readAsString(), 'preferences');
        expect(
          await File(p.join(sourceDatabases.path, 'dot.db')).readAsString(),
          'database',
        );
        if (fromDocuments) {
          expect(
            await File(p.join(sourceDatabases.path, 'dot.db-wal'))
                .readAsString(),
            'WAL',
          );
        }
        failActivation = false;
        await withActivation.copy();
        expect(await migration.newPreferences.readAsString(), 'preferences');
        expect(
          await File(p.join(sourceDatabases.path, 'dot.db')).exists(),
          !fromDocuments,
        );
      },
    );
  }
}
