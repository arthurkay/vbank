import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/data/dto/backup_dto.dart';
import 'package:vbank/src/data/dto/balance_dto.dart';
import 'package:vbank/src/data/dto/governance_dto.dart';
import 'package:vbank/src/data/dto/group_dto.dart';
import 'package:vbank/src/data/dto/invite_dto.dart';
import 'package:vbank/src/data/dto/loan_dto.dart';
import 'package:vbank/src/data/dto/meeting_dto.dart';
import 'package:vbank/src/data/dto/transaction_dto.dart';
import 'package:vbank/src/domain/backup.dart';
import 'package:vbank/src/domain/balance.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/identity.dart';
import 'package:vbank/src/domain/invites.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/data/repositories/backup_repository.dart';
import 'package:vbank/src/data/repositories/balance_repository.dart';
import 'package:vbank/src/data/repositories/governance_repository.dart';
import 'package:vbank/src/data/repositories/group_repository.dart';
import 'package:vbank/src/data/repositories/invite_repository.dart';
import 'package:vbank/src/data/repositories/loan_repository.dart';
import 'package:vbank/src/data/repositories/meeting_repository.dart';
import 'package:vbank/src/data/repositories/repository.dart';
import 'package:vbank/src/data/repositories/settings_repository.dart';
import 'package:vbank/src/data/repositories/transaction_repository.dart';
import 'package:vbank/src/domain/core/failure.dart';

import '../domain/fixtures.dart';
import 'test_db.dart';

void main() {
  group('repository error paths', () {
    test('attempt maps values and database errors', () async {
      expect((await attempt(() async => 42)).value, 42);
      expect(
        (await attempt(() async => throw StateError('nope'))).failure,
        isA<StorageFailure>(),
      );
    });

    test('corrupt rows surface as storage errors on reads', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlGroupRepository groups = SqlGroupRepository(db);
      final SqlTransactionRepository transactions = SqlTransactionRepository(
        db,
      );
      addTearDown(groups.close);
      addTearDown(transactions.close);
      // Bypass the DTOs: an enum value from the future.
      final Map<String, Object?> badGroup = GroupDto.toRow(testGroup('g-2'))
        ..['status'] = 'teleporting';
      await db.insert(
        'groups',
        badGroup,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      expect(
        (await groups.findById('g-2')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await groups.listAll()).failure,
        isA<StorageFailure>(),
      );

      // A corrupt member row sinks the whole group read.
      final Map<String, Object?> badMember =
          MemberDto.toRow('g-1', testMember('m'))
            ..['role'] = 'emperor';
      await db.insert(
        'members',
        badMember,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(
        (await groups.findById('g-1')).failure,
        isA<StorageFailure>(),
      );
    });

    test('corrupt rows surface as stream errors on watches', () async {
      final Database db = await openTestDb();
      final SqlGroupRepository groups = SqlGroupRepository(db);
      addTearDown(groups.close);
      final Map<String, Object?> badGroup = GroupDto.toRow(testGroup('g-2'))
        ..['status'] = 'teleporting';
      await db.insert('groups', badGroup);

      await expectLater(
        groups.watchGroups(),
        emitsError(isA<CorruptRow>()),
      );
    });

    test('corrupt child rows sink their list reads', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlLoanRepository loans = SqlLoanRepository(db);
      final SqlMeetingRepository meetings = SqlMeetingRepository(db);
      final SqlTransactionRepository transactions = SqlTransactionRepository(
        db,
      );
      addTearDown(loans.close);
      addTearDown(meetings.close);
      addTearDown(transactions.close);
      await loans.saveLoan(testLoan('l-1'));
      await meetings.save(testMeeting('m-1'));

      final Map<String, Object?> badSchedule = ScheduleDto.toRow(
        RepaymentSchedule(
          id: 's-1',
          loanId: 'l-1',
          installmentNumber: 1,
          expectedAmount: 10,
          dueDate: DateTime.utc(2026, 2, 8),
        ),
      )..['status'] = 'eventually';
      await db.insert(
        'schedules',
        badSchedule,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(
        (await loans.schedulesByLoan('l-1')).failure,
        isA<StorageFailure>(),
      );

      final Map<String, Object?> badAttendance = AttendanceDto.toRow(
        'm-1',
        const Attendance(peerId: 'a'),
      )..['status'] = 'maybe';
      await db.insert(
        'attendance',
        badAttendance,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(
        (await meetings.findById('m-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await meetings.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );

      await transactions.save(testTransaction('t-1'));
      final Map<String, Object?> badReversal = ReversalDto.toRow(
        TransactionReversal(
          id: 'r-1',
          originalTransactionId: 't-1',
          groupId: 'g-1',
          requestedByPeerId: 'a',
          reason: 'why',
          requestedAt: DateTime.utc(2026, 2, 2),
          requesterSignature: testSignature(),
        ),
      )..['status'] = 'shrug';
      await db.insert(
        'reversals',
        badReversal,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
      expect(
        (await transactions.reversalsByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
    });

    test('every list read rejects its corrupt rows', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlBackupRepository backups = SqlBackupRepository(db);
      final SqlBalanceRepository balances = SqlBalanceRepository(db);
      final SqlGovernanceRepository governance = SqlGovernanceRepository(db);
      final SqlInviteRepository invites = SqlInviteRepository(db);
      final SqlTransactionRepository transactions = SqlTransactionRepository(
        db,
      );
      final SqlLoanRepository loans = SqlLoanRepository(db);
      addTearDown(backups.close);
      addTearDown(balances.close);
      addTearDown(governance.close);
      addTearDown(invites.close);
      addTearDown(transactions.close);
      addTearDown(loans.close);
      Future<void> corrupt(
        String table,
        Map<String, Object?> row,
      ) => db.insert(
        table,
        row,
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      await corrupt(
        'backups',
        BackupDto.toRow(
          AppBackup(
            id: 'b',
            encryptedPayload: Uint8List.fromList(const [1]),
            groupIds: const ['g-1'],
            createdAt: DateTime.utc(2026, 1, 6),
            type: BackupType.full,
          ),
        )..['backup_type'] = 'none',
      );
      expect(
        (await backups.listBackups()).failure,
        isA<StorageFailure>(),
      );

      await corrupt(
        'identity',
        IdentityDto.toRow(
          UserIdentity(
            peerId: 'a',
            displayName: 'A',
            publicKey: testSignature(),
            createdAt: DateTime.utc(2026, 1, 5),
          ),
          // BLOB affinity never converts: text in a blob column stays
          // text and fails the cast on read.
        )..['public_key'] = 'not-bytes',
      );
      expect(
        (await backups.loadIdentity()).failure,
        isA<StorageFailure>(),
      );

      await corrupt(
        'balances',
        BalanceDto.toRow(
          Balance(
            peerId: 'a',
            groupId: 'g-1',
            lastUpdated: DateTime.utc(2026, 2, 1),
          ),
          // INTEGER affinity keeps unconvertible text as text.
        )..['last_updated'] = 'soon',
      );
      expect(
        (await balances.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );

      await corrupt(
        'removals',
        RemovalDto.toRow(
          MemberRemoval(
            id: 'r',
            groupId: 'g-1',
            removedPeerId: 'b',
            removedByPeerId: 'a',
            reason: 'why',
            action: RemovalAction.remove,
            removedAt: DateTime.utc(2026, 5, 1),
            adminSignature: testSignature(),
          ),
        )..['action'] = 'banish',
      );
      expect(
        (await governance.removalsByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );

      await corrupt(
        'transfers',
        TransferDto.toRow(
          OwnershipTransfer(
            id: 't',
            groupId: 'g-1',
            fromPeerId: 'a',
            toPeerId: 'b',
            transferredAt: DateTime.utc(2026, 5, 2),
            oldOwnerSignature: testSignature(),
            newOwnerSignature: testSignature(),
          ),
        )..['transferred_at'] = 'yesterday',
      );
      expect(
        (await governance.transfersByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );

      await corrupt(
        'invites',
        InviteDto.toRow(
          Invite(
            id: 'i',
            groupId: 'g-1',
            groupCid: 'cid',
            groupTopic: 't',
            inviterPeerId: 'a',
            inviterName: 'A',
            groupKey: Uint8List.fromList(const [9]),
            createdAt: DateTime.utc(2026, 4, 1),
            expiresAt: DateTime.utc(2026, 4, 8),
            nonce: Uint8List.fromList(const [7]),
            inviterSignature: testSignature(),
          ),
        )..['used'] = 'sometimes',
      );
      expect(
        (await invites.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );

      await transactions.save(testTransaction('t-1'));
      await corrupt(
        'transactions',
        TransactionDto.toRow(testTransaction('t-2'))..['type'] = 'teleport',
      );
      expect(
        (await transactions.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );

      await loans.saveLoan(testLoan('l-1'));
      await corrupt(
        'loans',
        LoanDto.toRow(testLoan('l-2'))..['status'] = 'limbo',
      );
      expect(
        (await loans.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await loans.schedulesByLoan('l-1')).value,
        isEmpty,
      );
    });

    test('every watch reports corruption as a stream error', () async {
      Future<void> expectWatchError<T>(Stream<List<T>> stream) =>
          expectLater(stream, emitsError(isA<CorruptRow>()));

      Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlTransactionRepository transactions = SqlTransactionRepository(
        db,
      );
      addTearDown(transactions.close);
      await db.insert(
        'transactions',
        TransactionDto.toRow(testTransaction('t'))..['type'] = 'teleport',
      );
      await expectWatchError(transactions.watchByGroup('g-1'));
      await db.close();

      db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlLoanRepository loans = SqlLoanRepository(db);
      addTearDown(loans.close);
      await db.insert(
        'loans',
        LoanDto.toRow(testLoan('l'))..['status'] = 'limbo',
      );
      await expectWatchError(loans.watchByGroup('g-1'));
      await db.close();

      db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlMeetingRepository meetings = SqlMeetingRepository(db);
      addTearDown(meetings.close);
      await db.insert(
        'meetings',
        MeetingDto.toRow(testMeeting('m'))..['status'] = 'eventually',
      );
      await expectWatchError(meetings.watchByGroup('g-1'));
      await db.close();

      db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlBalanceRepository balances = SqlBalanceRepository(db);
      addTearDown(balances.close);
      await db.insert(
        'balances',
        BalanceDto.toRow(
          Balance(
            peerId: 'a',
            groupId: 'g-1',
            lastUpdated: DateTime.utc(2026, 2, 1),
          ),
        )..['last_updated'] = 'soon',
      );
      await expectWatchError(balances.watchByGroup('g-1'));
      await db.close();
    });

    test('a closed database fails every read as a storage error', () async {
      final Database db = await openTestDbWithGroup(testGroup('g-1'));
      final SqlGroupRepository groups = SqlGroupRepository(db);
      final SqlTransactionRepository transactions = SqlTransactionRepository(
        db,
      );
      final SqlLoanRepository loans = SqlLoanRepository(db);
      final SqlMeetingRepository meetings = SqlMeetingRepository(db);
      final SqlInviteRepository invites = SqlInviteRepository(db);
      final SqlGovernanceRepository governance = SqlGovernanceRepository(db);
      final SqlBackupRepository backups = SqlBackupRepository(db);
      final SqlBalanceRepository balances = SqlBalanceRepository(db);
      final SqlSettingsRepository settings = SqlSettingsRepository(db);
      await db.close();

      expect((await groups.findById('g-1')).failure, isA<StorageFailure>());
      expect((await groups.listAll()).failure, isA<StorageFailure>());
      expect((await groups.delete('g-1')).failure, isA<StorageFailure>());
      expect(
        (await groups.save(testGroup('g-1'))).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await transactions.findById('t')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await transactions.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await transactions.save(testTransaction('t'))).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await transactions.markReversed('t')).failure,
        isA<StorageFailure>(),
      );
      expect((await loans.findById('l')).failure, isA<StorageFailure>());
      expect(
        (await loans.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await loans.saveLoan(testLoan('l'))).failure,
        isA<StorageFailure>(),
      );
      expect((await meetings.findById('m')).failure, isA<StorageFailure>());
      expect(
        (await meetings.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect((await invites.findById('i')).failure, isA<StorageFailure>());
      expect(
        (await invites.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await invites.markUsed('i')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await governance.dissolutionByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect((await backups.listBackups()).failure, isA<StorageFailure>());
      expect(
        (await backups.loadIdentity()).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await governance.removalsByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await governance.transfersByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect((await groups.listAll()).failure, isA<StorageFailure>());
      expect(
        (await loans.schedulesByLoan('l-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await meetings.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await transactions.reversalsByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await balances.find('a', 'g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await balances.listByGroup('g-1')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await settings.get('k')).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await settings.set('k', testSignature())).failure,
        isA<StorageFailure>(),
      );
      expect(
        (await settings.remove('k')).failure,
        isA<StorageFailure>(),
      );
      expect(
        CorruptRow(const NotFoundFailure('x')).toString(),
        contains('NotFoundFailure'),
      );
      expect(
        CorruptRow(const NotFoundFailure('x')).failure,
        isA<NotFoundFailure>(),
      );
    });
  });
}
