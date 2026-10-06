import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/repositories/backup_repository.dart';
import 'package:vbank/src/data/repositories/balance_repository.dart';
import 'package:vbank/src/data/repositories/settings_repository.dart';
import 'package:vbank/src/domain/backup.dart';
import 'package:vbank/src/domain/balance.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/identity.dart';

import '../domain/fixtures.dart';
import 'test_db.dart';

void main() {
  group('SqlBackupRepository', () {
    AppBackup testBackup() => AppBackup(
          id: 'b-1',
          encryptedPayload: Uint8List.fromList(const [1, 2]),
          groupIds: const ['g-1'],
          createdAt: DateTime.utc(2026, 1, 6),
          type: BackupType.full,
        );

    test('backups store, list and delete', () async {
      final Database db = await openTestDb();
      final SqlBackupRepository repo = SqlBackupRepository(db);
      addTearDown(repo.close);
      await repo.saveBackup(testBackup());

      expect(
        (await repo.listBackups()).value.map((AppBackup b) => b.id),
        ['b-1'],
      );

      expect((await repo.deleteBackup('b-1')).isOk, isTrue);
      expect((await repo.listBackups()).value, isEmpty);
    });

    test('identity saves, loads and clears', () async {
      final Database db = await openTestDb();
      final SqlBackupRepository repo = SqlBackupRepository(db);
      addTearDown(repo.close);

      expect((await repo.loadIdentity()).value, isNull);

      final UserIdentity identity = UserIdentity(
        peerId: 'a',
        displayName: 'A',
        publicKey: testSignature(),
        createdAt: DateTime.utc(2026, 1, 5),
      );
      await repo.saveIdentity(identity);

      expect((await repo.loadIdentity()).value, identity);

      expect((await repo.clearIdentity()).isOk, isTrue);
      expect((await repo.loadIdentity()).value, isNull);
    });
  });

  group('SqlBalanceRepository', () {
    Balance testBalance(String peer, double net) => Balance(
          peerId: peer,
          groupId: 'g-1',
          totalContributed: net,
          netBalance: net,
          lastUpdated: DateTime.utc(2026, 2, 1),
        );

    test('snapshots replace per group and find members', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlBalanceRepository repo = SqlBalanceRepository(db);
      addTearDown(repo.close);
      await repo.saveAll('g-1', [testBalance('a', 500), testBalance('b', 100)]);

      expect(
        (await repo.listByGroup('g-1')).value.map((b) => b.peerId),
        ['a', 'b'],
      );
      expect((await repo.find('a', 'g-1')).value.netBalance, 500);
      expect(
        (await repo.find('nope', 'g-1')).failure,
        isA<NotFoundFailure>(),
      );

      await repo.saveAll('g-1', [testBalance('a', 600)]);

      expect(
        (await repo.listByGroup('g-1')).value.map((b) => b.peerId),
        ['a'],
      );
    });

    test('watch follows recomputes', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlBalanceRepository repo = SqlBalanceRepository(db);
      addTearDown(repo.close);
      final List<List<Balance>> seen = [];
      final StreamSubscription<List<Balance>> sub =
          repo.watchByGroup('g-1').listen(seen.add);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(seen.single, isEmpty);

      await repo.saveAll('g-1', [testBalance('a', 500)]);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();

      expect(seen.last, hasLength(1));
    });
  });

  group('SqlSettingsRepository', () {
    test('settings store bytes, forget cleanly', () async {
      final Database db = await openTestDb();
      final SqlSettingsRepository repo = SqlSettingsRepository(db);
      addTearDown(repo.close);
      const String keyName = 'relay.addrs';
      final Uint8List value = Uint8List.fromList(
        utf8.encode('["/dns4/x/tcp/4001/p2p/QmY"]'),
      );

      expect((await repo.get(keyName)).value, isNull);
      expect((await repo.set(keyName, value)).isOk, isTrue);
      expect((await repo.get(keyName)).value, value);
      expect((await repo.remove(keyName)).isOk, isTrue);
      expect((await repo.get(keyName)).value, isNull);
      // Removing twice is fine.
      expect((await repo.remove(keyName)).isOk, isTrue);
    });
  });
}
