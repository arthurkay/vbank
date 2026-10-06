import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/key_service.dart';
import 'package:vbank/src/crypto/member_keys.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/reports.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'harness.dart';

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('GovernanceService reversals', () {
    test('request, approve and undo in one motion', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      ))
          .value;

      // Members can only dispute their own movements...
      expect(
        (await member.governance.requestReversal(
          groupId: gid,
          actingPeerId: 'member',
          transactionId: tx.id,
          reason: 'wrong amount',
        )).isOk,
        isTrue,
      );

      // ...and only one pending request per transaction.
      expect(
        (await member.governance.requestReversal(
          groupId: gid,
          actingPeerId: 'member',
          transactionId: tx.id,
          reason: 'again',
        )).failure,
        isA<ConflictFailure>(),
      );
      expect(
        (await member.governance.requestReversal(
          groupId: gid,
          actingPeerId: 'member',
          transactionId: tx.id,
          reason: '  ',
        )).failure,
        isA<ConflictFailure>(),
        reason: 'pending check precedes the blank check',
      );

      final reversals =
          await member.governance.reversalsForGroup(gid);
      final String rid = reversals.value.single.id;

      // The requester cannot decide their own request.
      expect(
        (await member.governance.decideReversal(
          groupId: gid,
          actingPeerId: 'member',
          reversalId: rid,
          approve: true,
        )).failure,
        isA<PermissionFailure>(),
      );

      final before = await owner.transactions.balances.listByGroup(gid);
      final double netBefore = before.value
          .firstWhere((b) => b.peerId == 'member')
          .netBalance;

      final decided = (await owner.governance.decideReversal(
        groupId: gid,
        actingPeerId: 'owner',
        reversalId: rid,
        approve: true,
      ))
          .value;
      expect(decided.status, ReversalStatus.approved);

      final after = await owner.transactions.balances.listByGroup(gid);
      expect(
        after.value.firstWhere((b) => b.peerId == 'member').netBalance,
        netBefore - 100,
      );
      expect(
        (await owner.transactions.getById(tx.id)).value.status,
        TransactionStatus.reversed,
      );

      // Decided is decided.
      expect(
        (await owner.governance.decideReversal(
          groupId: gid,
          actingPeerId: 'owner',
          reversalId: rid,
          approve: false,
        )).failure,
        isA<ConflictFailure>(),
      );
    });

    test('rejections stand without touching money', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      ))
          .value;
      await member.governance.requestReversal(
        groupId: gid,
        actingPeerId: 'member',
        transactionId: tx.id,
        reason: 'second thoughts',
      );
      final String rid =
          (await member.governance.reversalsForGroup(gid)).value.single.id;

      final decided = (await owner.governance.decideReversal(
        groupId: gid,
        actingPeerId: 'owner',
        reversalId: rid,
        approve: false,
      ))
          .value;
      expect(decided.status, ReversalStatus.rejected);
      expect(
        (await owner.transactions.getById(tx.id)).value.status,
        TransactionStatus.confirmed,
      );
    });

    test('remote reversals verify both signatures', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      ))
          .value;
      await member.governance.requestReversal(
        groupId: gid,
        actingPeerId: 'member',
        transactionId: tx.id,
        reason: 'wrong amount',
      );
      final String rid =
          (await member.governance.reversalsForGroup(gid)).value.single.id;
      final decided = (await owner.governance.decideReversal(
        groupId: gid,
        actingPeerId: 'owner',
        reversalId: rid,
        approve: true,
      ))
          .value;

      // Unknown requesters are not even verified.
      await world.keyFor('mallory');
      final TransactionReversal stranger = TransactionReversal(
        id: decided.id,
        originalTransactionId: decided.originalTransactionId,
        groupId: decided.groupId,
        requestedByPeerId: 'mallory',
        reason: decided.reason,
        requestedAt: decided.requestedAt,
        requesterSignature: decided.requesterSignature,
      );
      expect(
        (await owner.governance.importRemote(stranger)).failure,
        isA<NotFoundFailure>(),
      );

      // Tampered content fails the roster-key check.
      final TransactionReversal forged = TransactionReversal(
        id: decided.id,
        originalTransactionId: decided.originalTransactionId,
        groupId: decided.groupId,
        requestedByPeerId: decided.requestedByPeerId,
        reason: 'a different reason',
        requestedAt: decided.requestedAt,
        requesterSignature: decided.requesterSignature,
      );
      expect(
        (await owner.governance.importRemote(forged)).failure,
        isA<IntegrityFailure>(),
      );

      // The genuine record imports cleanly.
      expect((await owner.governance.importRemote(decided)).isOk, isTrue);
    });
  });

  group('GovernanceService dissolution', () {
    test('blockers, payouts and the dissolved flag', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');

      // Non-owners cannot dissolve.
      expect(
        (await world.stackFor('member').governance.dissolveGroup(
          groupId: gid,
          actingPeerId: 'member',
        )).failure,
        isA<PermissionFailure>(),
      );

      // Clean group: payouts for positive nets, then dissolved.
      final payouts = (await owner.governance.dissolveGroup(
        groupId: gid,
        actingPeerId: 'owner',
      ))
          .value;
      expect(payouts, hasLength(2));
      expect(
        (await owner.groups.getGroup(gid)).value.status,
        GroupStatus.dissolved,
      );

      // Dissolved groups refuse new business.
      expect(
        (await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 10,
        )).failure,
        isA<PermissionFailure>(),
      );
    });

    test('open loans and pending reversals block', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');
      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 100,
        );
      }
      final loan = (await member.loans.requestLoan(
        groupId: gid,
        borrowerPeerId: 'member',
        requestedAmount: 100,
        termWeeks: 4,
      ))
          .value;
      await owner.loans.approveLoan(
        loanId: loan.id,
        approvedAmount: 100,
        approverPeerId: 'owner',
      );
      await owner.loans.disburseLoan(
        loanId: loan.id,
        adminPeerId: 'owner',
      );

      final blockers = await owner.governance.dissolutionBlockers(gid);
      expect(blockers.value.single, contains('loan'));

      expect(
        (await owner.governance.dissolveGroup(
          groupId: gid,
          actingPeerId: 'owner',
        )).failure,
        isA<ConflictFailure>(),
      );
    });
  });

  group('GroupKeyService', () {
    test('passphrases stretch, randoms differ, rings merge forward', () async {
      expect(GroupKeyService.isPassphraseValid('  short '), isFalse);
      expect(GroupKeyService.isPassphraseValid('harvest moon'), isTrue);

      final SecretKey a = await GroupKeyService.deriveKey('harvest', 'g-1');
      final SecretKey b = await GroupKeyService.deriveKey('harvest', 'g-1');
      expect(await a.extractBytes(), await b.extractBytes());

      await world.keys.setRandom('g-1');
      await world.keys.setRandom('g-2');
      final SecretKey? k1 = await world.keys.getKey('g-1');
      final SecretKey? k2 = await world.keys.getKey('g-2');
      expect(k1, isNotNull);
      expect(await k1!.extractBytes(), isNot(await k2!.extractBytes()));
      expect(await world.keys.hasKey('g-1'), isTrue);
      expect(await world.keys.hasKey('nope'), isFalse);
      expect(
        (await world.keys.requireKey('nope')).failure,
        isA<NotFoundFailure>(),
      );

      // Rotation appends a version; import merges without regressing.
      final GroupKeyRing v1 = (await world.keys.ring('g-1'))!;
      expect(v1.currentVersion, 1);
      final GroupKeyRing v2 = (await world.keys.rotate('g-1')).value;
      expect(v2.currentVersion, 2);
      expect(await world.keys.keyFor('g-1', 1), isNotNull);
      expect(await world.keys.keyFor('g-1', 9), isNull);
      expect(
        (await world.keys.rotate('missing')).failure,
        isA<NotFoundFailure>(),
      );

      await world.keys.importRing('g-1', v1);
      expect(
        (await world.keys.ring('g-1'))!.currentVersion,
        2,
        reason: 'never moves backward',
      );

      final exported = await world.keys.exportAll();
      expect(exported.value.keys, contains('g-1'));
      await world.keys.removeKey('g-1');
      expect(await world.keys.hasKey('g-1'), isFalse);
      await world.keys.importAll(exported.value);
      expect(await world.keys.hasKey('g-1'), isTrue);
    });
  });

  group('ReportService', () {
    test('statements split by period with former members named', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      world.elapse(const Duration(days: 40));
      await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 500,
      );

      final report = (await world.reports.generateGroupReport(
        groupId: gid,
        period: DateTimePeriod(
          start: DateTime.utc(2026, 1, 1),
          end: DateTime.utc(2026, 12, 31),
        ),
      ))
          .value;

      expect(report.totalTransactions, 3);
      expect(report.totalContributions, 700);
      expect(report.memberStatements, hasLength(2));
      expect(
        report.memberStatements.map((s) => s.memberName),
        containsAll(['Owner', 'Member']),
      );
    });
  });
}
