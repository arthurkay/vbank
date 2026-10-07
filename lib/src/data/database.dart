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
      // Desktop builds bundle SQLite3MultipleCiphers, which starts with no
      // provider selected: pick the SQLCipher provider with SQLCipher-4
      // defaults, matching what the mobile builds get from sqflite_sqlcipher.
      // Real SQLCipher (phones) treats the first as a no-op and ignores the
      // unknown second pragma — either failure is swallowed, the gate below
      // is the real check either way.
      await db.execute("PRAGMA cipher = 'sqlcipher'");
      await db.execute('PRAGMA legacy = 4');
    } catch (_) {}
    // `cipher_version` answers on SQLCipher but stays silent on
    // SQLite3MultipleCiphers even while encrypting; there the selected
    // provider name is the proof. Both silent means plaintext SQLite.
    final List<Map<String, Object?>> version =
        await _pragmaOrEmpty(db, 'PRAGMA cipher_version');
    final List<Map<String, Object?>> provider =
        await _pragmaOrEmpty(db, 'PRAGMA cipher');
    if (version.isEmpty && provider.isEmpty) {
      throw StateError(
        'SQLCipher unavailable: refusing to touch a plaintext database',
      );
    }
    // PRAGMA key returns a result set on some builds (Android sqflite),
    // so it must go through rawQuery — execute() throws there.
    await db.rawQuery('PRAGMA key = "x\'$password\'"');
    // A wrong key only fails on first read: probe now.
    await db.rawQuery('SELECT count(*) FROM sqlite_master');
    await db.execute('PRAGMA foreign_keys = ON');
  }

  /// Reads a pragma, or nothing when the build does not know it (plain
  /// SQLite answers every unknown pragma with zero rows; some builds
  /// throw instead — both mean "not available").
  static Future<List<Map<String, Object?>>> _pragmaOrEmpty(
    Database db,
    String sql,
  ) async {
    try {
      return await db.rawQuery(sql);
    } catch (_) {
      return const [];
    }
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

      final File file = File(path);
      if (!file.existsSync() || await file.length() == 0) {
        // A zero-byte file holds nothing: an earlier failed open created it
        // and opening it keyed would only fail. Start fresh.
        if (await file.exists()) {
          await file.delete();
        }
        final Database db = await factory.openDatabase(
          path,
          options: options(),
        );
        await createSchema(db);
        return Ok(OpenResult(database: db, outcome: OpenOutcome.ready));
      }
      // Anything unreadable — legacy layout, corrupt file, or a key that no
      // longer fits — is set aside (never deleted) and rebuilt empty.
      // Records re-arrive from other members and the relay ledger.
      Database? db;
      try {
        db = await factory.openDatabase(path, options: options());
        if (await _isCurrentSchema(db)) {
          return Ok(OpenResult(database: db, outcome: OpenOutcome.ready));
        }
      } catch (_) {
        // Fall through to the rebuild below.
      }
      final Database? opened = db;
      if (opened != null) {
        try {
          await opened.close();
        } catch (_) {}
      }
      final String backupPath =
          '$path.legacy-${DateTime.now().millisecondsSinceEpoch}.bak';
      await file.rename(backupPath);
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
