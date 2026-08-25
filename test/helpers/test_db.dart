import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/core/storage/database.dart';

/// Points [AppDatabase] at a fresh in-memory SQLite (via sqflite_common_ffi)
/// so services/DAOs can be tested without a device. Call in `setUp`.
Future<void> useInMemoryDatabase() async {
  sqfliteFfiInit();
  await AppDatabase.useForTests(databaseFactoryFfi, inMemoryDatabasePath);
  // Force creation now so tests fail fast on schema errors.
  await AppDatabase.getInstance();
}

Future<void> closeTestDatabase() => AppDatabase.close();
