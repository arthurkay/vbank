import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/database.dart';
import 'package:vbank/src/data/schema.dart';
import 'package:vbank/src/domain/core/failure.dart';

/// Whether this host's sqlite3 has SQLCipher. The pubspec hook bundles
/// sqlite3mc for app builds; `flutter test` hosts may only have plaintext.
Future<bool> hasSqlCipher() async {
  sqfliteFfiInit();
  final Database db = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
  );
  final List<Map<String, Object?>> rows = await db.rawQuery(
    'PRAGMA cipher_version',
  );
  await db.close();
  return rows.isNotEmpty;
}

void main() {
  setUpAll(sqfliteFfiInit);

  late Directory dir;
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('vbank-db-test-');
  });
  tearDown(() async {
    await dir.delete(recursive: true);
  });

  /// Hex key: the app derives 32 bytes and hex-encodes them.
  const String key =
      '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

  Future<List<String>> tableNames(Database db) async {
    final List<Map<String, Object?>> rows = await db.rawQuery(
      "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name",
    );
    return [for (final Map<String, Object?> r in rows) r['name']! as String];
  }

  group('VBankDatabase', () {
    test('creates the full schema on a fresh file', () async {
      final String path = '${dir.path}/fresh.db';
      final OpenResult result = (await VBankDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        password: key,
        encrypted: false,
      ))
          .value;

      expect(result.outcome, OpenOutcome.ready);
      expect(result.backupPath, isNull);
      final List<String> tables = await tableNames(result.database);
      for (final String t in VBankSchema.tables) {
        expect(tables, contains(t), reason: t);
      }
      expect(await result.database.getVersion(), VBankSchema.version);
      await result.database.close();

      // Reopening is idempotent: still ready, nothing rebuilt.
      final OpenResult again = (await VBankDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        password: key,
        encrypted: false,
      ))
          .value;
      expect(again.outcome, OpenOutcome.ready);
      expect(again.backupPath, isNull);
      await again.database.close();
    });

    test('moves a legacy database aside and starts clean', () async {
      final String path = '${dir.path}/legacy.db';
      final Database legacy = await databaseFactoryFfi.openDatabase(path);
      await legacy.execute(
        'CREATE TABLE groups('
        'id TEXT PRIMARY KEY, name TEXT NOT NULL, data BLOB NOT NULL)',
      );
      await legacy.insert('groups', {
        'id': 'g-old',
        'name': 'Old Group',
        'data': Uint8List(0),
      });
      await legacy.close();

      final OpenResult result = (await VBankDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        password: key,
        encrypted: false,
      ))
          .value;

      expect(result.outcome, OpenOutcome.rebuilt);
      expect(result.backupPath, isNotNull);
      expect(File(result.backupPath!).existsSync(), isTrue);

      // The new database is empty and current.
      final List<String> tables = await tableNames(result.database);
      for (final String t in VBankSchema.tables) {
        expect(tables, contains(t), reason: t);
      }
      expect(
        await result.database.query('groups'),
        isEmpty,
      );
      await result.database.close();

      // The backup still holds the old row.
      final Database backup = await databaseFactoryFfi.openDatabase(
        result.backupPath!,
      );
      final List<Map<String, Object?>> rows = await backup.query('groups');
      expect(rows, hasLength(1));
      expect(rows.first['id'], 'g-old');
      await backup.close();
    });

    test('a wrong password fails closed', () async {
      if (!await hasSqlCipher()) {
        markTestSkipped('host sqlite3 has no SQLCipher build');
        return;
      }
      final String path = '${dir.path}/locked.db';
      final OpenResult first = (await VBankDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        password: key,
      ))
          .value;
      await first.database.close();

      final result = await VBankDatabase.open(
        factory: databaseFactoryFfi,
        path: path,
        password:
            'ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff',
      );

      expect(result.isErr, isTrue);
      expect(result.failure, isA<StorageFailure>());
    });
  });
}
