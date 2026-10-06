import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/database.dart';
import 'package:vbank/src/data/dto/group_dto.dart';
import 'package:vbank/src/domain/group.dart';

/// Opens a fresh plaintext database for repository tests: fast, hermetic,
/// no SQLCipher build needed. The schema and SQL are identical; only the
/// keying differs (covered by `database_test.dart` on cipher hosts).
Future<Database> openTestDb() async => openTestDbAt(inMemoryDatabasePath);

/// Opens a test database at [path]. Multi-device tests pass distinct temp
/// files so each harness owns its data; the default in-memory path must
/// not be shared across harnesses in one test.
Future<Database> openTestDbAt(String path) async {
  sqfliteFfiInit();
  final OpenResult result = (await VBankDatabase.open(
    factory: databaseFactoryFfi,
    path: path,
    password: '00',
    encrypted: false,
  ))
      .value;
  addTearDown(result.database.close);
  return result.database;
}

/// Opens a test database with [group] already stored, satisfying the
/// foreign keys that child rows (transactions, loans, meetings, balances)
/// require. Pass a group whose `id` matches the rows under test.
Future<Database> openTestDbWithGroup(Group group) async {
  final Database db = await openTestDb();
  await db.insert(
    'groups',
    GroupDto.toRow(group),
    conflictAlgorithm: ConflictAlgorithm.replace,
  );
  return db;
}
