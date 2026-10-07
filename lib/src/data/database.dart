import 'dart:io';

import 'package:sqflite_sqlcipher/sqflite.dart';

import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import 'schema.dart';

/// How [VBankDatabase.open] went.
enum OpenOutcome {
  /// Fresh file or our own v1 schema: existing data is intact.
  ready,

  /// A pre-rewrite (or otherwise unknown) layout was found: the old file
  /// was moved aside to [OpenResult.backupPath] and an empty v1 schema was
  /// created. Records re-arrive from other members and the relay ledger —
  /// devices are copies, never the sole original.
  rebuilt,
}

/// An opened database plus how it got there.
final class OpenResult {
  /// The ready database.
  final Database database;

  /// Whether anything had to be rebuilt.
  final OpenOutcome outcome;

  /// Where the previous file went, when [outcome] is [OpenOutcome.rebuilt].
  final String? backupPath;

  /// Creates an open result.
  const OpenResult({
    required this.database,
    required this.outcome,
    this.backupPath,
  });
}

/// Opens the encrypted app database.
///
/// The [factory] is injected so tests pass an in-memory one: the app passes
/// the platform factory (`sqflite_sqlcipher` on phones, FFI on desktops) and
/// tests pass `databaseFactoryFfi`.
///
/// [password] is a hex string (the app derives 32 bytes via HKDF and hex
/// encodes them). It is applied with `PRAGMA key` on every connection rather
/// than the `password:` parameter, so mobile and desktop key identically.
abstract final class VBankDatabase {
  /// Keys an open [db] connection and proves it: refuses plaintext-only
  /// SQLite builds and wrong keys loudly instead of corrupting data.
  ///
  /// Public for tests and tools that open databases outside [open].
  static Future<void> keyConnection(Database db, String password) async {
    if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(password)) {
      throw ArgumentError.value(password, 'password', 'must be hex');
    }
    try {
      // Desktop sqlite3 bundles SQLCipher but starts in plaintext mode:
      // select the cipher before anything else. Mobile builds (already
      // SQLCipher) reject the unknown pragma — ignored, the version
      // check below is the real gate either way.
      await db.execute("PRAGMA cipher = 'sqlcipher'");
    } catch (_) {}
    final List<Map<String, Object?>> cipher =
        await db.rawQuery('PRAGMA cipher_version');
    if (cipher.isEmpty) {
      throw StateError(
        'SQLCipher unavailable: refusing to touch a plaintext database '
        '(on a Linux desktop this means the sqlite3 build has no cipher '
        'compiled in — phones ship their own through sqflite_sqlcipher)',
      );
    }
    await db.execute('PRAGMA key = "x\'$password\'"');
    // A wrong key only fails on first read: probe now.
    await db.rawQuery('SELECT count(*) FROM sqlite_master');
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Opens (creating when absent) the database at [path] with [password].
  ///
  /// [encrypted] is true in the app. Tests pass false to run on plaintext
  /// SQLite (not every test host bundles SQLCipher); the cipher gate and
  /// keying are skipped, foreign keys are still enforced.
  static Future<Result<OpenResult>> open({
    required DatabaseFactory factory,
    required String path,
    required String password,
    bool encrypted = true,
  }) async {
    try {
      // No `version:` here on purpose: legacy files carry version 0 and
      // sqflite throws on a version mismatch without an onUpgrade. We
      // inspect the layout ourselves and stamp the version when we create.
      OpenDatabaseOptions options() => OpenDatabaseOptions(
            onConfigure: (Database db) async {
              if (encrypted) {
                await keyConnection(db, password);
              } else {
                await db.execute('PRAGMA foreign_keys = ON');
              }
            },
          );
      Future<void> createSchema(Database db) async {
        for (final String ddl in VBankSchema.createStatements) {
          await db.execute(ddl);
        }
        await db.setVersion(VBankSchema.version);
      }

      if (!File(path).existsSync()) {
        final Database db = await factory.openDatabase(
          path,
          options: options(),
        );
        await createSchema(db);
        return Ok(OpenResult(database: db, outcome: OpenOutcome.ready));
      }
      final Database db = await factory.openDatabase(
        path,
        options: options(),
      );
      if (await _isCurrentSchema(db)) {
        return Ok(OpenResult(database: db, outcome: OpenOutcome.ready));
      }
      final String backupPath =
          '$path.legacy-${DateTime.now().millisecondsSinceEpoch}.bak';
      await db.close();
      await File(path).rename(backupPath);
      final Database rebuilt = await factory.openDatabase(
        path,
        options: options(),
      );
      await createSchema(rebuilt);
      return Ok(
        OpenResult(
          database: rebuilt,
          outcome: OpenOutcome.rebuilt,
          backupPath: backupPath,
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// True when [db] already runs our schema: stamped version plus the
  /// flattened config column that no legacy database has.
  static Future<bool> _isCurrentSchema(Database db) async {
    final int version = await db.getVersion();
    if (version != VBankSchema.version) {
      return false;
    }
    final List<Map<String, Object?>> columns =
        await db.rawQuery('PRAGMA table_info(groups)');
    return columns.any(
      (Map<String, Object?> c) => c['name'] == 'contribution_amount',
    );
  }
}
