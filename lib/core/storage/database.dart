import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_sqlcipher/sqflite.dart';

import '../security/device_secret.dart';

/// Local storage. The database file is encrypted with SQLCipher
/// (DESIGN_PLAN §11/§29); the key is derived from the per-install
/// [DeviceSecret] with HKDF-SHA256, so it never exists outside this device.
///
/// Note: the plan derives the DB key from *the* group key + device secret,
/// which is ambiguous once a device belongs to several groups. We derive it
/// from the device secret alone — the group keys themselves are rows inside
/// the (encrypted) database.
///
/// Two engines, one behaviour: Android, iOS and macOS use `sqflite_sqlcipher`
/// (native SQLCipher). Linux and Windows have no such plugin, so they open the
/// same file through `sqflite_common_ffi` against the SQLite3MultipleCiphers
/// build of `package:sqlite3` (selected by `hooks.user_defines.sqlite3.source`
/// in pubspec.yaml), put it in SQLCipher-compatible mode and key it with
/// `PRAGMA key`. SQLite3MC is bundled, so Linux and Windows need no system
/// SQLCipher package.
class AppDatabase {
  static Database? _database;

  /// Bump when the schema changes and add a step to [_onUpgrade].
  static const schemaVersion = 6;

  static const _fileName = 'vbank.db';

  // --- test hooks -----------------------------------------------------------
  static DatabaseFactory? _testFactory;
  static String? _testPath;

  /// Route all DB access through [factory] (e.g. `databaseFactoryFfi`) at
  /// [path] (`inMemoryDatabasePath` for unit tests). Disables encryption.
  static Future<void> useForTests(DatabaseFactory factory, String path) async {
    await close();
    _testFactory = factory;
    _testPath = path;
  }

  static Future<Database> getInstance() async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  static Future<Database> _initDatabase() async {
    final testFactory = _testFactory;
    if (testFactory != null) {
      return testFactory.openDatabase(
        _testPath!,
        options: OpenDatabaseOptions(
          version: schemaVersion,
          onConfigure: _onConfigure,
          onCreate: _onCreate,
          onUpgrade: _onUpgrade,
        ),
      );
    }

    final password = await _databasePassword();

    if (_useFfi) return _openWithFfi(password);

    final dbPath = await getDatabasesPath();
    final path = join(dbPath, _fileName);

    await _migratePlaintextIfNeeded(path, password);

    return openDatabase(
      path,
      password: password,
      version: schemaVersion,
      onConfigure: _onConfigure,
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );
  }

  /// Linux and Windows: sqflite_common_ffi + SQLCipher-enabled sqlite3.
  static bool get _useFfi => Platform.isLinux || Platform.isWindows;

  static Future<Database> _openWithFfi(String password) async {
    ffi.sqfliteFfiInit();
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final path = join(dir.path, _fileName);

    return ffi.databaseFactoryFfi.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: schemaVersion,
        onConfigure: (db) async {
          // Order matters: pick the cipher, then key the connection before any
          // other statement — everything after this is read and written
          // encrypted.
          await db.execute("PRAGMA cipher = 'sqlcipher'");
          await db.execute('PRAGMA key = "x\'$password\'"');
          await _assertKeyed(db);
          await _onConfigure(db);
        },
        onCreate: _onCreate,
        onUpgrade: _onUpgrade,
      ),
    );
  }

  /// A wrong key (or a plain sqlite3 without SQLCipher) only fails when the
  /// first page is read, so probe it and fail loudly rather than corrupting.
  static Future<void> _assertKeyed(Database db) async {
    try {
      await db.rawQuery('SELECT count(*) FROM sqlite_master');
    } catch (e) {
      throw StateError(
        'Could not open the encrypted database — the sqlite3 library in use '
        'probably has no encryption support. Check '
        'hooks.user_defines.sqlite3.source in pubspec.yaml. ($e)',
      );
    }
  }

  /// SQLCipher passphrase: HKDF-SHA256(device secret, info "vbank-local-db"),
  /// hex-encoded (SQLCipher derives its own page key from this with PBKDF2).
  static Future<String> _databasePassword() async {
    final secret = await DeviceSecret.get();
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final key = await hkdf.deriveKey(
      secretKey: SecretKey(secret),
      nonce: List.filled(16, 0),
      info: utf8.encode('vbank-local-db'),
    );
    final bytes = await key.extractBytes();
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Databases created before encryption was enabled are plain SQLite files
  /// (header "SQLite format 3\0"). Re-encrypt them in place using SQLCipher's
  /// `sqlcipher_export`, preserving schema, data and user_version.
  static Future<void> _migratePlaintextIfNeeded(String path, String password) async {
    final file = File(path);
    if (!await file.exists()) return;

    final raf = await file.open();
    final header = await raf.read(16);
    await raf.close();
    const plainHeader = 'SQLite format 3';
    if (header.length < 16 || String.fromCharCodes(header.sublist(0, 15)) != plainHeader) return;

    final encryptedPath = '$path.enc';
    final encFile = File(encryptedPath);
    if (await encFile.exists()) await encFile.delete();

    final plain = await openDatabase(path); // no password → plaintext
    try {
      final version = Sqflite.firstIntValue(
            await plain.rawQuery('PRAGMA user_version'),
          ) ??
          0;
      await plain.execute(
        "ATTACH DATABASE '${encryptedPath.replaceAll("'", "''")}' AS enc KEY '$password'",
      );
      await plain.rawQuery("SELECT sqlcipher_export('enc')");
      await plain.execute('PRAGMA enc.user_version = $version');
      await plain.execute('DETACH DATABASE enc');
    } finally {
      await plain.close();
    }

    final backupPath = '$path.plaintext.bak';
    await file.rename(backupPath);
    await encFile.rename(path);
    // Journal of the old plaintext DB, if any, is now meaningless.
    final journal = File('$path-journal');
    if (await journal.exists()) await journal.delete();
    // Do not keep an unencrypted copy around.
    await File(backupPath).delete();
  }

  static Future<void> _onConfigure(Database db) async {
    // The schema declares REFERENCES constraints; SQLite ignores them unless
    // foreign keys are switched on per connection.
    await db.execute('PRAGMA foreign_keys = ON');
  }

  static Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('ALTER TABLE user_identity ADD COLUMN private_key BLOB');
    }
    if (oldVersion < 3) {
      await _createGroupKeysTable(db);
    }
    if (oldVersion < 4) {
      // Sequence numbers are per *author* (DESIGN_PLAN §19: transactions are
      // append-only and never conflict). A per-group unique sequence made two
      // offline members collide on the same number.
      await db.execute('DROP INDEX IF EXISTS idx_transactions_group_seq');

      // Offline queue state (DESIGN_PLAN §21) lives on the transaction row.
      await db.execute("ALTER TABLE transactions ADD COLUMN sync_status TEXT DEFAULT 'queued'");
      await db.execute('ALTER TABLE transactions ADD COLUMN sync_attempts INTEGER DEFAULT 0');
      await db.execute('ALTER TABLE transactions ADD COLUMN last_sync_attempt_at INTEGER');
      await db.execute('ALTER TABLE transactions ADD COLUMN last_sync_error TEXT');
      await db.execute("UPDATE transactions SET sync_status = 'synced' WHERE synced = 1");
      await db.execute('DROP TABLE IF EXISTS pending_transactions');

      // Invites carry nonce + inviter signature for one-use enforcement.
      await db.execute('ALTER TABLE invites ADD COLUMN nonce BLOB');
      await db.execute('ALTER TABLE invites ADD COLUMN inviter_peer_id TEXT');
      await db.execute('ALTER TABLE invites ADD COLUMN inviter_signature BLOB');
      await db.execute('ALTER TABLE invites ADD COLUMN used_by_peer_id TEXT');

      // Metadata timestamp for §19 tie-breaks.
      await db.execute('ALTER TABLE groups ADD COLUMN updated_at INTEGER');
      await db.execute('UPDATE groups SET updated_at = created_at WHERE updated_at IS NULL');

      // Loans: link repayments to loans.
      await db.execute('ALTER TABLE transactions ADD COLUMN loan_id TEXT');

      // DESIGN_PLAN §13: only owners/admins write. The *author* (signer) of a
      // transaction is therefore usually not the member whose money moves
      // (`from_peer_id`). Existing rows were self-authored.
      await db.execute('ALTER TABLE transactions ADD COLUMN author_peer_id TEXT');
      await db.execute('UPDATE transactions SET author_peer_id = from_peer_id WHERE author_peer_id IS NULL');
    }
    if (oldVersion < 5) {
      // Invite links carry a one-time secret; the invite keeps the group key
      // wrapped under it (InviteKeyWrap) for the snapshot header.
      await db.execute('ALTER TABLE invites ADD COLUMN wrapped_key BLOB');
    }
    if (oldVersion < 6) {
      // Key rotation: members publish an X25519 key, groups keep every key
      // version, removals can be lifted by the owner.
      await db.execute('ALTER TABLE members ADD COLUMN enc_key BLOB');
      await db.execute('ALTER TABLE member_removals ADD COLUMN lifted INTEGER DEFAULT 0');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS group_key_history (
          group_id TEXT NOT NULL,
          version INTEGER NOT NULL,
          key BLOB NOT NULL,
          PRIMARY KEY (group_id, version)
        )
      ''');
      await db.execute('INSERT OR IGNORE INTO group_key_history (group_id, version, key) SELECT group_id, 1, key FROM group_keys');
    }
    await _createIndexes(db);
  }

  /// Group symmetric keys (DESIGN_PLAN §12): derived from the group
  /// passphrase. One per group; every payload for that group on IPFS is
  /// encrypted with it.
  static Future<void> _createGroupKeysTable(DatabaseExecutor db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_keys (
        group_id TEXT PRIMARY KEY,
        key BLOB NOT NULL,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS group_key_history (
        group_id TEXT NOT NULL,
        version INTEGER NOT NULL,
        key BLOB NOT NULL,
        PRIMARY KEY (group_id, version)
      )
    ''');
  }

  static Future<void> _createIndexes(DatabaseExecutor db) async {
    await db.execute('''
      CREATE UNIQUE INDEX IF NOT EXISTS idx_transactions_author_seq
      ON transactions (group_id, author_peer_id, sequence_number)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_transactions_sync
      ON transactions (sync_status)
    ''');
    await db.execute('''
      CREATE INDEX IF NOT EXISTS idx_repayment_schedules_loan
      ON repayment_schedules (loan_id, installment_number)
    ''');
  }

  static Future<void> _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE user_identity (
        peer_id TEXT PRIMARY KEY,
        display_name TEXT NOT NULL,
        public_key BLOB NOT NULL,
        private_key BLOB,
        created_at INTEGER NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE groups (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        data BLOB NOT NULL,
        config_data BLOB NOT NULL,
        cid TEXT,
        require_approval INTEGER DEFAULT 0,
        status TEXT DEFAULT 'active',
        created_at INTEGER NOT NULL,
        sequence_number INTEGER DEFAULT 0,
        updated_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE members (
        peer_id TEXT NOT NULL,
        group_id TEXT NOT NULL REFERENCES groups(id),
        name TEXT NOT NULL,
        role TEXT DEFAULT 'member',
        status TEXT DEFAULT 'active',
        public_key BLOB NOT NULL,
        joined_at INTEGER NOT NULL,
        has_outstanding_loan INTEGER DEFAULT 0,
        enc_key BLOB,
        PRIMARY KEY (peer_id, group_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE transactions (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL REFERENCES groups(id),
        from_peer_id TEXT NOT NULL,
        to_peer_id TEXT NOT NULL,
        type TEXT NOT NULL,
        amount REAL NOT NULL,
        currency TEXT DEFAULT 'ZMW',
        note TEXT,
        timestamp INTEGER NOT NULL,
        sequence_number INTEGER NOT NULL,
        sender_signature BLOB NOT NULL,
        status TEXT DEFAULT 'confirmed',
        cid TEXT,
        synced INTEGER DEFAULT 0,
        sync_status TEXT DEFAULT 'queued',
        sync_attempts INTEGER DEFAULT 0,
        last_sync_attempt_at INTEGER,
        last_sync_error TEXT,
        loan_id TEXT,
        author_peer_id TEXT
      )
    ''');

    await db.execute('''
      CREATE TABLE transaction_reversals (
        id TEXT PRIMARY KEY,
        original_transaction_id TEXT NOT NULL REFERENCES transactions(id),
        group_id TEXT NOT NULL,
        requested_by_peer_id TEXT NOT NULL,
        approved_by_peer_id TEXT,
        reason TEXT NOT NULL,
        status TEXT DEFAULT 'pending',
        requested_at INTEGER NOT NULL,
        resolved_at INTEGER,
        requester_signature BLOB NOT NULL,
        approver_signature BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE loans (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL REFERENCES groups(id),
        borrower_peer_id TEXT NOT NULL,
        requested_amount REAL NOT NULL,
        approved_amount REAL,
        interest_rate REAL NOT NULL,
        term_weeks INTEGER NOT NULL,
        reason TEXT,
        status TEXT DEFAULT 'pending',
        requested_at INTEGER NOT NULL,
        approved_at INTEGER,
        approved_by_peer_id TEXT,
        disbursed_at INTEGER,
        completed_at INTEGER,
        defaulted_at INTEGER,
        borrower_signature BLOB NOT NULL,
        approver_signature BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE repayment_schedules (
        id TEXT PRIMARY KEY,
        loan_id TEXT NOT NULL REFERENCES loans(id),
        installment_number INTEGER NOT NULL,
        expected_amount REAL NOT NULL,
        due_date INTEGER NOT NULL,
        paid_amount REAL DEFAULT 0,
        paid_at INTEGER,
        is_overdue INTEGER DEFAULT 0,
        penalty REAL DEFAULT 0,
        status TEXT DEFAULT 'pending'
      )
    ''');

    await db.execute('''
      CREATE TABLE balances (
        peer_id TEXT NOT NULL,
        group_id TEXT NOT NULL REFERENCES groups(id),
        total_contributed REAL DEFAULT 0,
        total_loaned REAL DEFAULT 0,
        total_repaid REAL DEFAULT 0,
        total_withdrawn REAL DEFAULT 0,
        total_penalties REAL DEFAULT 0,
        outstanding_loan REAL DEFAULT 0,
        net_balance REAL DEFAULT 0,
        last_updated INTEGER NOT NULL,
        PRIMARY KEY (peer_id, group_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE meetings (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL REFERENCES groups(id),
        scheduled_at INTEGER NOT NULL,
        status TEXT DEFAULT 'scheduled',
        notes TEXT,
        total_collected REAL DEFAULT 0,
        completed_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE attendance (
        meeting_id TEXT NOT NULL REFERENCES meetings(id),
        peer_id TEXT NOT NULL,
        status TEXT DEFAULT 'absent',
        contributed INTEGER DEFAULT 0,
        contribution_time INTEGER,
        PRIMARY KEY (meeting_id, peer_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE invites (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL REFERENCES groups(id),
        cid TEXT,
        used INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        expires_at INTEGER NOT NULL,
        nonce BLOB,
        inviter_peer_id TEXT,
        inviter_signature BLOB,
        used_by_peer_id TEXT,
        wrapped_key BLOB
      )
    ''');

    await db.execute('''
      CREATE TABLE member_removals (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        removed_peer_id TEXT NOT NULL,
        removed_by_peer_id TEXT NOT NULL,
        reason TEXT NOT NULL,
        has_outstanding_loan INTEGER DEFAULT 0,
        outstanding_amount REAL DEFAULT 0,
        action TEXT NOT NULL,
        removed_at INTEGER NOT NULL,
        admin_signature BLOB NOT NULL,
        lifted INTEGER DEFAULT 0
      )
    ''');

    await db.execute('''
      CREATE TABLE ownership_transfers (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        from_peer_id TEXT NOT NULL,
        to_peer_id TEXT NOT NULL,
        transferred_at INTEGER NOT NULL,
        old_owner_signature BLOB NOT NULL,
        new_owner_signature BLOB NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE group_dissolutions (
        id TEXT PRIMARY KEY,
        group_id TEXT NOT NULL,
        initiated_by_peer_id TEXT NOT NULL,
        initiated_at INTEGER NOT NULL,
        status TEXT DEFAULT 'initiating',
        all_loans_settled INTEGER DEFAULT 0,
        funds_distributed INTEGER DEFAULT 0,
        completed_at INTEGER
      )
    ''');

    await db.execute('''
      CREATE TABLE app_backups (
        id TEXT PRIMARY KEY,
        encrypted_payload BLOB NOT NULL,
        created_at INTEGER NOT NULL,
        version INTEGER DEFAULT 1,
        backup_type TEXT NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE node_config (
        key TEXT PRIMARY KEY,
        value BLOB NOT NULL
      )
    ''');

    await db.execute('''
      CREATE TABLE notification_schedules (
        id TEXT PRIMARY KEY,
        group_id TEXT,
        notification_type TEXT NOT NULL,
        scheduled_at INTEGER NOT NULL,
        payload TEXT,
        is_active INTEGER DEFAULT 1
      )
    ''');

    await _createGroupKeysTable(db);
    await _createIndexes(db);
  }

  static Future<void> close() async {
    final db = _database;
    _database = null;
    if (db != null && db.isOpen) await db.close();
  }
}
