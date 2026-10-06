import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/data/dto/backup_dto.dart';
import 'package:vbank/src/data/dto/dto.dart';
import 'package:vbank/src/data/dto/balance_dto.dart';
import 'package:vbank/src/data/dto/governance_dto.dart';
import 'package:vbank/src/data/dto/group_dto.dart';
import 'package:vbank/src/data/dto/invite_dto.dart';
import 'package:vbank/src/data/dto/loan_dto.dart';
import 'package:vbank/src/data/dto/meeting_dto.dart';
import 'package:vbank/src/data/dto/transaction_dto.dart';
import 'package:vbank/src/domain/backup.dart';
import 'package:vbank/src/domain/balance.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/identity.dart';
import 'package:vbank/src/domain/invites.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';

import '../domain/fixtures.dart';

void main() {
  group('DTO round-trips', () {
    test('Group keeps config, members stay separate', () {
      final Group group = testGroup(
        'g',
        members: [testMember('m', role: MemberRole.owner)],
        sequenceNumber: 7,
      ).copyWith(cid: () => 'cid-1');

      final Group back = GroupDto.fromRow(GroupDto.toRow(group)).value;

      // Members ride in their own table; the group row carries the rest.
      expect(back, group.copyWith(members: const []));
      expect(back.members, isEmpty);
      expect(back.config.meetingTime.format(), '09:00');
    });

    test('Member keeps keys and standing', () {
      final Member member = testMember(
        'm',
        role: MemberRole.admin,
        status: MemberStatus.suspended,
      ).copyWith(
        hasOutstandingLoan: true,
        encKey: Uint8List.fromList(const [8]),
      );

      expect(MemberDto.fromRow(MemberDto.toRow('g', member)).value, member);
    });

    test('Transaction keeps authorship and links', () {
      final Transaction tx = testTransaction(
        't',
        type: TransactionType.repayment,
        loanId: 'l-1',
      );

      final Transaction back =
          TransactionDto.fromRow(TransactionDto.toRow(tx)).value;

      expect(back, tx);
      expect(back.authorPeerId, 'alice');
      expect(back.loanId, 'l-1');
    });

    test('Reversal keeps its decision trail', () {
      final TransactionReversal reversal = TransactionReversal(
        id: 'r',
        originalTransactionId: 't',
        groupId: 'g',
        requestedByPeerId: 'a',
        approvedByPeerId: 'b',
        reason: 'wrong amount',
        status: ReversalStatus.approved,
        requestedAt: DateTime.utc(2026, 2, 2),
        resolvedAt: DateTime.utc(2026, 2, 3),
        requesterSignature: testSignature(),
        approverSignature: testSignature(),
      );

      expect(
        ReversalDto.fromRow(ReversalDto.toRow(reversal)).value,
        reversal,
      );
    });

    test('Loan keeps its lifecycle stamps', () {
      final LoanRequest loan = testLoan(
        'l',
        approvedAmount: 300,
        status: LoanStatus.repaying,
      ).copyWith(
        approvedAt: DateTime.utc(2026, 2, 2),
        approvedByPeerId: 'admin',
        disbursedAt: DateTime.utc(2026, 2, 3),
        completedAt: DateTime.utc(2026, 3, 3),
        approverSignature: testSignature(),
      );

      expect(LoanDto.fromRow(LoanDto.toRow(loan)).value, loan);
    });

    test('defaulted loans keep their write-off stamp', () {
      final LoanRequest loan = LoanRequest(
        id: 'l',
        groupId: 'g',
        borrowerPeerId: 'a',
        requestedAmount: 100,
        approvedAmount: 100,
        interestRate: 0.1,
        termWeeks: 4,
        status: LoanStatus.defaulted,
        requestedAt: DateTime.utc(2026, 2, 1),
        borrowerSignature: testSignature(),
        defaultedAt: DateTime.utc(2026, 4, 1),
      );

      expect(LoanDto.fromRow(LoanDto.toRow(loan)).value, loan);
    });

    test('whole-number reals survive an int storage round', () {
      expect(Dto.real(const {'a': 5}, 'a'), 5.0);
      expect(Dto.real(const {'a': 5.5}, 'a'), 5.5);
      expect(Dto.realOrNull(const {'a': 5}, 'a'), 5.0);
      expect(Dto.realOrNull(const {'a': null}, 'a'), isNull);
    });

    test('Schedule keeps payment progress', () {
      final RepaymentSchedule schedule = RepaymentSchedule(
        id: 's',
        loanId: 'l',
        installmentNumber: 2,
        expectedAmount: 82.5,
        dueDate: DateTime.utc(2026, 2, 15),
        paidAmount: 40,
        paidAt: DateTime.utc(2026, 2, 14),
        isOverdue: true,
        penalty: 4.25,
        status: RepaymentStatus.overdue,
      );

      expect(
        ScheduleDto.fromRow(ScheduleDto.toRow(schedule)).value,
        schedule,
      );
    });

    test('Meeting keeps attendance separately', () {
      final Meeting meeting = testMeeting(
        'm',
        attendance: [
          Attendance(
            peerId: 'a',
            status: MeetingAttendanceStatus.present,
            contributed: true,
            contributionTime: DateTime.utc(2026, 3, 7, 10),
          ),
        ],
      ).copyWith(
        status: MeetingStatus.completed,
        totalCollected: 200,
        completedAt: DateTime.utc(2026, 3, 7, 12),
      );
      final Map<String, Object?> row = MeetingDto.toRow(meeting);
      final List<Attendance> attendance = [
        for (final Attendance a in meeting.attendance)
          AttendanceDto.fromRow(AttendanceDto.toRow('m', a)).value,
      ];

      expect(MeetingDto.fromRow(row, attendance).value, meeting);
    });

    test('Invite keeps its ticket fields', () {
      final Invite invite = Invite(
        id: 'i',
        groupId: 'g',
        groupCid: 'cid',
        groupTopic: 'vbank/group/g',
        inviterPeerId: 'a',
        inviterName: 'A',
        wrappedKey: Uint8List.fromList(const [9]),
        createdAt: DateTime.utc(2026, 4, 1),
        expiresAt: DateTime.utc(2026, 4, 8),
        used: true,
        nonce: Uint8List.fromList(const [7]),
        inviterSignature: testSignature(),
      );

      expect(InviteDto.fromRow(InviteDto.toRow(invite)).value, invite);
    });

    test('Removal keeps its ban state', () {
      final MemberRemoval removal = MemberRemoval(
        id: 'r',
        groupId: 'g',
        removedPeerId: 'b',
        removedByPeerId: 'a',
        reason: 'moved away',
        hasOutstandingLoan: true,
        outstandingAmount: 50,
        action: RemovalAction.settleAndRemove,
        removedAt: DateTime.utc(2026, 5, 1),
        adminSignature: testSignature(),
        lifted: true,
      );

      expect(RemovalDto.fromRow(RemovalDto.toRow(removal)).value, removal);
    });

    test('Transfer and dissolution round-trip', () {
      final OwnershipTransfer transfer = OwnershipTransfer(
        id: 't',
        groupId: 'g',
        fromPeerId: 'a',
        toPeerId: 'b',
        transferredAt: DateTime.utc(2026, 5, 2),
        oldOwnerSignature: testSignature(),
        newOwnerSignature: testSignature(),
      );
      final GroupDissolution dissolution = GroupDissolution(
        id: 'd',
        groupId: 'g',
        initiatedByPeerId: 'a',
        initiatedAt: DateTime.utc(2026, 6, 1),
        status: DissolutionStatus.distributingFunds,
        allLoansSettled: true,
        completedAt: DateTime.utc(2026, 6, 20),
      );

      expect(
        TransferDto.fromRow(TransferDto.toRow(transfer)).value,
        transfer,
      );
      expect(
        DissolutionDto.fromRow(DissolutionDto.toRow(dissolution)).value,
        dissolution,
      );
    });

    test('Backup joins and splits group ids', () {
      final AppBackup backup = AppBackup(
        id: 'b',
        encryptedPayload: Uint8List.fromList(const [1, 2]),
        groupIds: const ['g-1', 'g-2'],
        createdAt: DateTime.utc(2026, 1, 6),
        type: BackupType.selective,
      );

      final AppBackup back = BackupDto.fromRow(BackupDto.toRow(backup)).value;

      expect(back, backup);
      expect(BackupDto.toRow(backup)['group_ids'], 'g-1,g-2');
    });

    test('Identity and balance round-trip', () {
      final UserIdentity identity = UserIdentity(
        peerId: 'a',
        displayName: 'A',
        publicKey: testSignature(),
        createdAt: DateTime.utc(2026, 1, 5),
      );
      final Balance balance = Balance(
        peerId: 'a',
        groupId: 'g',
        totalContributed: 500,
        outstandingLoan: 200,
        netBalance: 300,
        lastUpdated: DateTime.utc(2026, 2, 1),
      );

      expect(
        IdentityDto.fromRow(IdentityDto.toRow(identity)).value,
        identity,
      );
      expect(BalanceDto.fromRow(BalanceDto.toRow(balance)).value, balance);
    });
  });

  group('DTO failures', () {
    test('missing columns fail as storage errors', () {
      expect(
        GroupDto.fromRow(const {}).failure,
        isA<StorageFailure>(),
      );
      expect(
        TransactionDto.fromRow(const {'id': 't'}).failure,
        isA<StorageFailure>(),
      );
    });

    test('unknown enums fail loudly instead of defaulting', () {
      final Transaction tx = testTransaction('t');
      final Map<String, Object?> row = TransactionDto.toRow(tx)
        ..['type'] = 'teleport';

      expect(
        TransactionDto.fromRow(row).failure,
        isA<StorageFailure>(),
      );
    });

    test('every table rejects an empty row', () {
      const Map<String, Object?> empty = {};
      expect(GroupDto.fromRow(empty).isErr, isTrue);
      expect(MemberDto.fromRow(empty).isErr, isTrue);
      expect(TransactionDto.fromRow(empty).isErr, isTrue);
      expect(ReversalDto.fromRow(empty).isErr, isTrue);
      expect(LoanDto.fromRow(empty).isErr, isTrue);
      expect(ScheduleDto.fromRow(empty).isErr, isTrue);
      expect(MeetingDto.fromRow(empty, const []).isErr, isTrue);
      expect(AttendanceDto.fromRow(empty).isErr, isTrue);
      expect(InviteDto.fromRow(empty).isErr, isTrue);
      expect(RemovalDto.fromRow(empty).isErr, isTrue);
      expect(TransferDto.fromRow(empty).isErr, isTrue);
      expect(DissolutionDto.fromRow(empty).isErr, isTrue);
      expect(BackupDto.fromRow(empty).isErr, isTrue);
      expect(IdentityDto.fromRow(empty).isErr, isTrue);
      expect(BalanceDto.fromRow(empty).isErr, isTrue);
    });

    test('bad meeting times fail with a named reason', () {
      final Group group = testGroup('g');
      final Map<String, Object?> row = GroupDto.toRow(group)
        ..['meeting_time'] = '25:99';

      expect(
        GroupDto.fromRow(row).failure,
        isA<ValidationFailure>(),
      );
    });
  });
}
