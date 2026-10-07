import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Run before SharedPreferences, identity loading and opening any database.
Future<void> migrateMacData(Directory supportDirectory) async {
  if (!Platform.isMacOS) return;
  final home = Platform.environment['HOME'];
  if (home == null) {
    throw StateError('macOS home directory unavailable');
  }
  final container = Directory(
    p.join(home, 'Library', 'Containers', 'com.bemooks.dot', 'Data'),
  );
  if (!await container.exists()) return;
  final legacySupport = Directory(
    p.join(container.path, 'Library', 'Application Support', 'com.bemooks.dot'),
  );
  // sqflite_darwin's handleGetDatabasesPath uses NSDocumentDirectory, not
  // Application Support: sandboxed = container/Data/Documents, otherwise
  // the user's Documents directory. Query the installed plugin for the target.
  final databases = Directory(await getDatabasesPath());
  if (p.isWithin(container.path, supportDirectory.path) ||
      p.isWithin(container.path, databases.path)) {
    return;
  }
  await MacDataMigration(
    oldSupport: legacySupport,
    newSupport: supportDirectory,
    oldDatabases: Directory(p.join(container.path, 'Documents')),
    newDatabases: databases,
    oldPreferences: File(
      p.join(container.path, 'Library', 'Preferences', 'com.bemooks.dot.plist'),
    ),
    newPreferences: File(
      p.join(home, 'Library', 'Preferences', 'com.bemooks.dot.plist'),
    ),
    activatePreferences: () async {
      // AppKit may have cached this domain before Dart started. Import the
      // target plist into UserDefaults before shared_preferences first reads it.
      const channel = MethodChannel('dot/migration');
      if (await channel.invokeMethod<bool>('reloadPreferences') != true) {
        throw const FileSystemException('Migrated preferences unavailable');
      }
    },
  ).copy();
}

/// Copies only into missing destinations. Original container data stays intact.
/// On failure roll back this attempt and abort startup, rather than minting a
/// new identity over a partial migration and losing existing pairing trust.
class MacDataMigration {
  final Directory oldSupport;
  final Directory newSupport;
  final Directory oldDatabases;
  final Directory newDatabases;
  final File oldPreferences;
  final File newPreferences;
  final Future<void> Function()? activatePreferences;

  const MacDataMigration({
    required this.oldSupport,
    required this.newSupport,
    required this.oldDatabases,
    required this.newDatabases,
    required this.oldPreferences,
    required this.newPreferences,
    this.activatePreferences,
  });

  Future<void> copy() async {
    final created = <FileSystemEntity>[];
    final marker = File(p.join(newSupport.path, '.sandbox-migration'));
    try {
      final targetDb = File(p.join(newDatabases.path, 'dot.db'));
      final targetSecrets = Directory(p.join(newSupport.path, 'secrets'));
      final resuming = await marker.exists();
      final hasNewData =
          !resuming &&
          (await _exists(targetDb.path) || await _exists(targetSecrets.path));
      if (!hasNewData) {
        var sourceDb = File(p.join(oldDatabases.path, 'dot.db'));
        // Also accept the Application Support layout of older/manual builds.
        if (!await sourceDb.exists()) {
          sourceDb = File(p.join(oldSupport.path, 'dot.db'));
        }
        final hasLegacyData =
            await sourceDb.exists() ||
            await Directory(p.join(oldSupport.path, 'secrets')).exists();
        if (resuming && !hasLegacyData) {
          throw const FileSystemException(
            'Migration source unavailable for retry',
          );
        }
        if (hasLegacyData) {
          // A crash after copying secrets but before the database must resume,
          // not mistake the partially copied identity for an existing install.
          await _directory(newSupport, created);
          if (!resuming) await marker.writeAsString('copying', flush: true);
          for (final folder in ['secrets', 'files']) {
            final source = Directory(p.join(oldSupport.path, folder));
            if (await source.exists()) {
              await _copyTree(
                source,
                Directory(p.join(newSupport.path, folder)),
                created,
                private: folder == 'secrets',
              );
            }
          }
          if (await sourceDb.exists()) {
            // Preserve committed WAL transactions when the previous app did
            // not checkpoint on shutdown. Copy the entire SQLite file family.
            for (final suffix in ['', '-wal', '-shm', '-journal']) {
              final source = File('${sourceDb.path}$suffix');
              if (await source.exists()) {
                await _copyFile(
                  source,
                  File('${targetDb.path}$suffix'),
                  created,
                );
              }
            }
          }
        }
      }
      // Preferences are independent: never overwrite existing user settings.
      if (await oldPreferences.exists() &&
          !await _exists(newPreferences.path)) {
        await _copyFile(oldPreferences, newPreferences, created);
      }
      if (await oldPreferences.exists() && await newPreferences.exists()) {
        await activatePreferences?.call();
      }
      if (await marker.exists()) await marker.delete();
      if (created.isNotEmpty) debugPrint('DOT macOS data migration succeeded.');
    } catch (_) {
      for (final entity in created.reversed) {
        try {
          await entity.delete();
        } catch (_) {}
      }
      debugPrint('DOT macOS data migration failed. Original data retained.');
      rethrow;
    }
  }

  static Future<bool> _exists(String path) async =>
      await FileSystemEntity.type(path, followLinks: false) !=
      FileSystemEntityType.notFound;

  static Future<void> _directory(
    Directory target,
    List<FileSystemEntity> created, {
    bool private = false,
  }) async {
    final type = await FileSystemEntity.type(target.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await _directory(target.parent, created);
      await target.create();
      created.add(target);
    } else if (type != FileSystemEntityType.directory) {
      throw const FileSystemException(
        'Migration destination is not a directory',
      );
    }
    if (private && !Platform.isWindows) await _chmod('700', target.path);
  }

  static Future<void> _copyTree(
    Directory source,
    Directory target,
    List<FileSystemEntity> created, {
    required bool private,
  }) async {
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.directory) {
      throw const FileSystemException('Migration source is not a directory');
    }
    await _directory(target, created, private: private);
    await for (final entity in source.list(followLinks: false)) {
      final destination = p.join(target.path, p.basename(entity.path));
      if (entity is Directory) {
        await _copyTree(
          entity,
          Directory(destination),
          created,
          private: private,
        );
      } else if (entity is File) {
        await _copyFile(entity, File(destination), created, private: private);
      } else {
        throw const FileSystemException('Migration source contains a link');
      }
    }
  }

  static Future<void> _copyFile(
    File source,
    File target,
    List<FileSystemEntity> created, {
    bool private = false,
  }) async {
    if (await _exists(target.path)) return;
    if (await FileSystemEntity.type(source.path, followLinks: false) !=
        FileSystemEntityType.file) {
      throw const FileSystemException('Migration source is not a file');
    }
    await _directory(target.parent, created);
    final staging = await target.parent.createTemp('.dot-migration-');
    try {
      final temporary = await source.copy(p.join(staging.path, 'copy'));
      if (private && !Platform.isWindows) await _chmod('600', temporary.path);
      if (await _exists(target.path)) {
        throw const FileSystemException('Migration destination changed');
      }
      await temporary.rename(target.path);
      created.add(target);
    } finally {
      await staging.delete(recursive: true);
    }
  }

  static Future<void> _chmod(String mode, String path) async {
    final result = await Process.run('chmod', [mode, path]);
    if (result.exitCode != 0) {
      throw const FileSystemException('Migration secret permissions');
    }
  }
}
