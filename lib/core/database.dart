import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

/// Opens the single local DOT database. Pass [factory] in tests
/// (sqflite_common_ffi) and [path] = inMemoryDatabasePath.
class DotDatabase {
  static const _version = 1;

  static Future<Database> open({DatabaseFactory? factory, String? path}) async {
    final f = factory ?? databaseFactory;
    final dbPath = path ?? p.join(await f.getDatabasesPath(), 'dot.db');
    return f.openDatabase(
      dbPath,
      options: OpenDatabaseOptions(
        version: _version,
        singleInstance: dbPath != inMemoryDatabasePath,
        onCreate: (db, v) async {
          await db.execute('''
            CREATE TABLE items (
              id TEXT PRIMARY KEY,
              type TEXT NOT NULL,
              title TEXT NOT NULL,
              body TEXT NOT NULL,
              file_name TEXT,
              file_size INTEGER,
              mime_type TEXT,
              sha256 TEXT,
              local_path TEXT,
              origin_device_id TEXT NOT NULL,
              origin_name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              pinned INTEGER NOT NULL DEFAULT 0,
              deleted INTEGER NOT NULL DEFAULT 0,
              etag TEXT NOT NULL,
              parent_etag TEXT,
              dirty INTEGER NOT NULL DEFAULT 0,
              sync_state TEXT NOT NULL,
              progress REAL NOT NULL DEFAULT 0,
              conflict_of TEXT
            )''');
          await db.execute('CREATE INDEX items_dirty ON items(dirty)');
          await db.execute('''
            CREATE TABLE devices (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              platform TEXT NOT NULL,
              public_key TEXT NOT NULL,
              cert_fingerprint TEXT,
              host TEXT,
              port INTEGER,
              paired_at INTEGER NOT NULL,
              last_connected_at INTEGER
            )''');
        },
      ),
    );
  }
}
