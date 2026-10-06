import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/backup.dart';
import 'package:vbank/src/domain/balance.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/currency.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/identity.dart';
import 'package:vbank/src/domain/invites.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/reports.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'fixtures.dart';

/// The equality contract every entity obeys: a no-change `copyWith` is
/// equal with a matching hash, and each field participates in equality.
/// This catches the classic slip of adding a field but forgetting it in
/// `==`, `hashCode` or `copyWith`.
void main() {
  group('equality contracts', () {
    test('Member', () {
      final Member m = testMember('a', role: MemberRole.admin);

      expect(m.copyWith(), m);
      expect(m.copyWith().hashCode, m.hashCode);
      expect(m == m.copyWith(name: 'Other'), isFalse);
      expect(m == m.copyWith(status: MemberStatus.suspended), isFalse);
      expect(
        m == m.copyWith(hasOutstandingLoan: true),
        isFalse,
      );
      expect(
        m == m.copyWith(encKey: Uint8List.fromList(const [9])),
        isFalse,
      );
    });

    test('GroupConfig', () {
      const GroupConfig c = GroupConfig(
        groupId: 'g',
        contributionAmount: 100,
      );

      expect(c.copyWith(), c);
      expect(c.copyWith().hashCode, c.hashCode);
      expect(c == c.copyWith(currency: 'USD'), isFalse);
      expect(c == c.copyWith(frequency: ContributionFrequency.weekly), isFalse);
    });

    test('Group', () {
      final Group g = testGroup('g', members: [testMember('m')]);

      expect(g.copyWith(), g);
      expect(g.copyWith().hashCode, g.hashCode);
      expect(g == g.copyWith(name: 'Other'), isFalse);
      expect(g == g.copyWith(requireApproval: true), isFalse);
      expect(g == g.copyWith(status: GroupStatus.dissolved), isFalse);
    });

    test('Transaction', () {
      final Transaction t = testTransaction('t');

      expect(t.copyWith(), t);
      expect(t.copyWith().hashCode, t.hashCode);
      expect(
        t == t.copyWith(status: TransactionStatus.reversed),
        isFalse,
      );
      expect(t == t.copyWith(note: 'hi'), isFalse);
    });

    test('TransactionReversal', () {
      TransactionReversal testReversal() => TransactionReversal(
            id: 'r',
            originalTransactionId: 't',
            groupId: 'g',
            requestedByPeerId: 'a',
            reason: 'why',
            requestedAt: DateTime.utc(2026, 2, 2),
            requesterSignature: testSignature(),
          );
      final TransactionReversal r = testReversal();

      expect(r.copyWith(), r);
      expect(r.copyWith().hashCode, r.hashCode);
      expect(
        r == r.copyWith(status: ReversalStatus.rejected),
        isFalse,
      );
    });

    test('LoanRequest', () {
      final LoanRequest l = testLoan('l');

      expect(l.copyWith(), l);
      expect(l.copyWith().hashCode, l.hashCode);
      expect(l == l.copyWith(approvedAmount: 100), isFalse);
      expect(
        l == l.copyWith(status: LoanStatus.approved),
        isFalse,
      );
    });

    test('RepaymentSchedule', () {
      final RepaymentSchedule s = RepaymentSchedule(
        id: 's',
        loanId: 'l',
        installmentNumber: 1,
        expectedAmount: 10,
        dueDate: DateTime.utc(2026, 2, 8),
      );

      expect(s.copyWith(), s);
      expect(s.copyWith().hashCode, s.hashCode);
      expect(s == s.copyWith(penalty: 1), isFalse);
      expect(s == s.copyWith(isOverdue: true), isFalse);
    });

    test('Meeting and Attendance', () {
      final Meeting m = testMeeting('m');
      const Attendance a = Attendance(peerId: 'x');

      expect(m.copyWith(), m);
      expect(m.copyWith().hashCode, m.hashCode);
      expect(m == m.copyWith(notes: 'n'), isFalse);
      expect(a.copyWith(), a);
      expect(a == a.copyWith(contributed: true), isFalse);
    });

    test('Invite', () {
      Invite testInvite() => Invite(
            id: 'i',
            groupId: 'g',
            groupCid: 'cid',
            groupTopic: 't',
            inviterPeerId: 'a',
            inviterName: 'A',
            groupKey: Uint8List.fromList(const [1]),
            createdAt: DateTime.utc(2026, 4, 1),
            expiresAt: DateTime.utc(2026, 4, 8),
            nonce: Uint8List.fromList(const [2]),
            inviterSignature: testSignature(),
          );
      final Invite i = testInvite();

      expect(i.copyWith(), i);
      expect(i.copyWith().hashCode, i.hashCode);
    });

    test('UserIdentity and IdentityBackup', () {
      final UserIdentity u = UserIdentity(
        peerId: 'a',
        displayName: 'A',
        publicKey: testSignature(),
        createdAt: DateTime.utc(2026, 1, 5),
      );
      final IdentityBackup b = IdentityBackup(
        encryptedPrivateKey: Uint8List.fromList(const [1]),
        peerId: 'a',
        backedUpAt: DateTime.utc(2026, 1, 6),
      );

      expect(u.copyWith(), u);
      expect(u.copyWith().hashCode, u.hashCode);
      expect(b == b, isTrue);
      expect(b.hashCode, b.hashCode);
    });

    test('MemberRemoval', () {
      MemberRemoval testRemoval() => MemberRemoval(
            id: 'r',
            groupId: 'g',
            removedPeerId: 'b',
            removedByPeerId: 'a',
            reason: 'why',
            action: RemovalAction.suspend,
            removedAt: DateTime.utc(2026, 5, 1),
            adminSignature: testSignature(),
          );
      final MemberRemoval r = testRemoval();

      expect(r.copyWith(), r);
      expect(r.copyWith().hashCode, r.hashCode);
    });

    test('OwnershipTransfer', () {
      OwnershipTransfer testTransfer() => OwnershipTransfer(
            id: 't',
            groupId: 'g',
            fromPeerId: 'a',
            toPeerId: 'b',
            transferredAt: DateTime.utc(2026, 5, 2),
            oldOwnerSignature: testSignature(),
            newOwnerSignature: testSignature(),
          );

      expect(testTransfer(), testTransfer());
      expect(testTransfer().hashCode, testTransfer().hashCode);
    });

    test('GroupDissolution', () {
      final GroupDissolution d = GroupDissolution(
        id: 'd',
        groupId: 'g',
        initiatedByPeerId: 'a',
        initiatedAt: DateTime.utc(2026, 6, 1),
      );

      expect(d.copyWith(), d);
      expect(d.copyWith().hashCode, d.hashCode);
      expect(
        d == d.copyWith(status: DissolutionStatus.completed),
        isFalse,
      );
    });

    test('AppBackup', () {
      AppBackup testBackup() => AppBackup(
            id: 'b',
            encryptedPayload: Uint8List.fromList(const [1]),
            groupIds: const ['g'],
            createdAt: DateTime.utc(2026, 1, 6),
            type: BackupType.selective,
          );

      expect(testBackup(), testBackup());
      expect(testBackup().hashCode, testBackup().hashCode);
    });

    test('Balance', () {
      final Balance b = Balance(
        peerId: 'a',
        groupId: 'g',
        lastUpdated: DateTime.utc(2026, 2, 1),
      );

      expect(b.copyWith(), b);
      expect(b.copyWith().hashCode, b.hashCode);
      expect(b == b.copyWith(netBalance: 1), isFalse);
    });

    test('CurrencyInfo and reports', () {
      const CurrencyInfo info = CurrencyInfo(
        symbol: 'ZK',
        name: 'Zambian Kwacha',
        decimals: 2,
        isDefault: true,
      );

      expect(info, CurrencyConfig.defaultCurrency);
      expect(info.hashCode, CurrencyConfig.defaultCurrency.hashCode);
      expect(
        info ==
            const CurrencyInfo(
              symbol: 'ZK',
              name: 'Zambian Kwacha',
              decimals: 2,
            ),
        isFalse,
      );

      const MemberStatement s = MemberStatement(
        peerId: 'a',
        memberName: 'A',
        totalContributed: 1,
        totalLoaned: 2,
        totalRepaid: 3,
        outstandingBalance: 4,
      );
      expect(s, s);
      expect(s.hashCode, s.hashCode);

      final DateTimePeriod p = DateTimePeriod(
        start: DateTime.utc(2026, 1, 1),
        end: DateTime.utc(2026, 1, 2),
      );
      expect(p, p);
    });

    test('every Failure constructs', () {
      // Non-const construction: const invocations fold at compile time and
      // never execute the constructor body for coverage.
      expect(NetworkFailure(peer: 'a').peer, 'a');
      expect(IntegrityFailure('s').subject, 's');
      expect(PermissionFailure('a').action, 'a');
      expect(ValidationFailure('r').reason, 'r');
      expect(NotFoundFailure('s').subject, 's');
      expect(ConflictFailure('s').subject, 's');
      expect(
        StorageFailure('boom').cause,
        'boom',
      );
    });
  });

  group('branch closures', () {
    test('valid groups pass validation', () {
      final Group group = testGroup('g', members: [testMember('m')]);

      expect(group.validate().isOk, isTrue);
    });

    test('invite cid lists compare by content', () {
      final Group a = testGroup('g').copyWith(inviteCids: ['cid-1']);
      final Group b = testGroup('g').copyWith(inviteCids: ['cid-2']);

      expect(a == b, isFalse);
      expect(a == a.copyWith(inviteCids: ['cid-1']), isTrue);
    });

    test('members compare published key bytes', () {
      final Member a = testMember('m').copyWith(
        encKey: Uint8List.fromList(const [1]),
      );
      final Member b = testMember('m').copyWith(
        encKey: Uint8List.fromList(const [2]),
      );
      final Member c = testMember('m').copyWith(
        encKey: Uint8List.fromList(const [1]),
      );

      expect(a == b, isFalse);
      expect(a, c);
    });

    test('reversals compare approver signatures', () {
      TransactionReversal testReversal(Uint8List? sig) => TransactionReversal(
            id: 'r',
            originalTransactionId: 't',
            groupId: 'g',
            requestedByPeerId: 'a',
            reason: 'why',
            requestedAt: DateTime.utc(2026, 2, 2),
            requesterSignature: testSignature(),
            approverSignature: sig,
          );
      final TransactionReversal a = testReversal(
        Uint8List.fromList(const [1]),
      );
      final TransactionReversal b = testReversal(
        Uint8List.fromList(const [2]),
      );

      expect(a == b, isFalse);
      expect(
        a,
        testReversal(Uint8List.fromList(const [1])),
      );
    });

    test('loans compare approver signatures', () {
      LoanRequest testSigned(Uint8List? sig) => testLoan('l').copyWith(
            approverSignature: sig,
          );

      expect(
        testSigned(Uint8List.fromList(const [1])) ==
            testSigned(Uint8List.fromList(const [2])),
        isFalse,
      );
      expect(
        testSigned(Uint8List.fromList(const [1])),
        testSigned(Uint8List.fromList(const [1])),
      );
    });

    test('approved-but-undisbursed loans commit principal', () {
      final Map<String, LoanProgress> all = LoanProgress.forGroup(
        [testLoan('l', approvedAmount: 400, status: LoanStatus.approved)],
        const [],
      );

      expect(all['l']!.principalOutstanding, 400);
    });

    test('withdrawals leave and reversals skip the fund', () {
      final GroupFund fund = GroupFund.compute(
        [
          testTransaction('c', amount: 1000),
          testTransaction(
            'w',
            type: TransactionType.withdrawal,
            fromPeerId: 'alice',
            toPeerId: 'alice',
            amount: 200,
          ),
          testTransaction('x', type: TransactionType.reversal, amount: 50),
        ],
        const [],
      );

      expect(fund.available, 800);
      expect(
        fund,
        const GroupFund(
          available: 800,
          lentOut: 0,
          interestExpected: 0,
        ),
      );
      expect(
        fund.hashCode,
        const GroupFund(
          available: 800,
          lentOut: 0,
          interestExpected: 0,
        ).hashCode,
      );
    });

    test('attendance hashes and compares by content', () {
      const Attendance a = Attendance(
        peerId: 'x',
        status: MeetingAttendanceStatus.present,
      );

      expect(a.hashCode, a.hashCode);
      final Meeting m1 = testMeeting(
        'm',
        attendance: const [Attendance(peerId: 'x')],
      );
      final Meeting m2 = testMeeting(
        'm',
        attendance: const [
          Attendance(
            peerId: 'y',
          ),
        ],
      );

      expect(m1 == m2, isFalse);
    });

    test('meeting times print as HH:MM', () {
      expect(
        const MeetingTime(hour: 9, minute: 5).toString(),
        'MeetingTime(09:05)',
      );
    });

    test('identity backups compare by value', () {
      IdentityBackup testBackup() => IdentityBackup(
            encryptedPrivateKey: Uint8List.fromList(const [1]),
            peerId: 'a',
            backedUpAt: DateTime.utc(2026, 1, 6),
          );

      expect(testBackup(), testBackup());
      expect(testBackup().hashCode, testBackup().hashCode);
    });

    test('periods compare by value', () {
      DateTimePeriod testPeriod() => DateTimePeriod(
            start: DateTime.utc(2026, 1, 1),
            end: DateTime.utc(2026, 1, 2),
          );

      expect(testPeriod(), testPeriod());
      expect(testPeriod().hashCode, testPeriod().hashCode);
      expect(
        testPeriod() ==
            DateTimePeriod(
              start: DateTime.utc(2026, 1, 1),
              end: DateTime.utc(2026, 1, 3),
            ),
        isFalse,
      );
    });

    test('statements compare by value', () {
      MemberStatement testStatement() => MemberStatement(
            peerId: 'a',
            memberName: 'A',
            totalContributed: 1,
            totalLoaned: 2,
            totalRepaid: 3,
            outstandingBalance: 4,
          );

      expect(testStatement(), testStatement());
      expect(testStatement().hashCode, testStatement().hashCode);
    });

    test('reports compare statements by content', () {
      GroupReport testReport(List<MemberStatement> statements) => GroupReport(
            groupId: 'g',
            period: DateTimePeriod(
              start: DateTime.utc(2026, 1, 1),
              end: DateTime.utc(2026, 1, 31),
            ),
            totalContributions: 1,
            totalLoansDisbursed: 0,
            totalLoansRepaid: 0,
            totalPenalties: 0,
            groupFundBalance: 1,
            totalMeetings: 0,
            totalTransactions: 1,
            memberStatements: statements,
          );
      MemberStatement testStatement(String peer) => MemberStatement(
            peerId: peer,
            memberName: peer,
            totalContributed: 1,
            totalLoaned: 0,
            totalRepaid: 0,
            outstandingBalance: 0,
          );

      expect(
        testReport([testStatement('a')]),
        testReport([testStatement('a')]),
      );
      expect(
        testReport([testStatement('a')]).hashCode,
        testReport([testStatement('a')]).hashCode,
      );
      expect(
        testReport([testStatement('a')]) == testReport([testStatement('b')]),
        isFalse,
      );
      expect(
        testReport([testStatement('a')]) ==
            testReport([testStatement('a'), testStatement('b')]),
        isFalse,
      );
    });
  });
}
