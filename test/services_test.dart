import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/crypto/identity.dart';
import 'package:vbank/core/crypto/signing.dart';
import 'package:vbank/core/storage/invite_dao.dart';
import 'package:vbank/models/group.dart';
import 'package:vbank/models/loan.dart';
import 'package:vbank/models/transaction.dart';
import 'package:vbank/services/governance_service.dart';
import 'package:vbank/services/group_key_service.dart';
import 'package:vbank/services/group_service.dart';
import 'package:vbank/services/invite_service.dart';
import 'package:vbank/services/loan_service.dart';
import 'package:vbank/services/transaction_service.dart';

import 'helpers/test_db.dart';

/// A fake device: identity + key pair.
class Person {
  final GeneratedIdentity g;
  Person(this.g);
  String get peerId => g.identity.peerId;
  Uint8List get pub => g.identity.publicKey;
  SimpleKeyPair get kp => g.keyPair;
  Member member({MemberRole role = MemberRole.member}) => Member(
        peerId: peerId,
        name: g.identity.displayName,
        role: role,
        joinedAt: DateTime.utc(2026, 1, 1),
        publicKey: pub,
      );
  static Future<Person> create(String name) async => Person(await IdentityManager.createIdentity(name));
}

void main() {
  late GroupService groups;
  late TransactionService txs;
  late LoanService loans;
  late GovernanceService gov;
  late InviteService invites;
  late Person owner, admin, member, outsider;
  late Group circle;

  setUp(() async {
    await useInMemoryDatabase();
    final keys = GroupKeyService();
    invites = InviteService();
    groups = GroupService(groupKeyService: keys, inviteService: invites);
    txs = TransactionService();
    loans = LoanService(groupService: groups, transactionService: txs);
    gov = GovernanceService(groupService: groups, transactionService: txs);

    owner = await Person.create('Owner');
    admin = await Person.create('Admin');
    member = await Person.create('Member');
    outsider = await Person.create('Outsider');

    circle = await groups.createGroup(
      name: 'Test Circle',
      config: const GroupConfig(groupId: '', contributionAmount: 50, minContributionsForLoan: 2, maxLoanMultiplier: 3),
      passphrase: 'test-circle-2026',
      ownerPeerId: owner.peerId,
      ownerName: 'Owner',
      ownerPublicKey: owner.pub,
      ownerKeyPair: owner.kp,
    );
    await groups.addMember(groupId: circle.id, member: admin.member(role: MemberRole.admin));
    await groups.addMember(groupId: circle.id, member: member.member());
  });

  tearDown(closeTestDatabase);

  group('Signed payloads survive storage and the wire', () {
    // Regression: `DateTime.now()` has microseconds, the database keeps
    // milliseconds, and records are re-read from the database before they are
    // sent — so signatures made over the in-memory timestamp never verified on
    // the receiving phone ("invalid author signature" in the two-device E2E).
    test('a transaction re-read from the database still verifies', () async {
      final tx = await txs.createTransaction(
          groupId: circle.id, authorPeerId: owner.peerId, authorKeyPair: owner.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 20);
      final stored = (await txs.getByGroupId(circle.id)).where((t) => t.id == tx.id).single;
      expect(await txs.verifySignature(stored, owner.pub), isTrue);
      final wire = Transaction.fromJson(jsonDecode(jsonEncode(stored.toJson())) as Map<String, dynamic>);
      expect(await txs.verifySignature(wire, owner.pub), isTrue);
    });
  });

  group('Permissions (DESIGN_PLAN §13)', () {
    test('members cannot record transactions; admins can', () async {
      expect(
        () => txs.createTransaction(
          groupId: circle.id, authorPeerId: member.peerId, authorKeyPair: member.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 50),
        throwsA(isA<PermissionException>()),
      );
      final tx = await txs.createTransaction(
          groupId: circle.id, authorPeerId: admin.peerId, authorKeyPair: admin.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 50);
      expect(tx.authorPeerId, admin.peerId);
      expect(tx.fromPeerId, member.peerId);
      expect(await txs.verifySignature(tx, admin.pub), isTrue);
      expect(await txs.verifySignature(tx, member.pub), isFalse);
    });

    test('only the owner promotes/demotes/removes; owner cannot be removed', () async {
      expect(
        () => groups.updateMemberRole(groupId: circle.id, actingPeerId: admin.peerId, peerId: member.peerId, newRole: MemberRole.admin),
        throwsA(isA<PermissionException>()),
      );
      await groups.updateMemberRole(groupId: circle.id, actingPeerId: owner.peerId, peerId: member.peerId, newRole: MemberRole.admin);
      expect((await groups.getMember(circle.id, member.peerId))!.role, MemberRole.admin);

      expect(
        () => groups.removeMember(groupId: circle.id, actingPeerId: owner.peerId, actingKeyPair: owner.kp, peerId: owner.peerId, reason: 'x'),
        throwsA(isA<PermissionException>()),
      );
      expect(
        () => groups.updateMemberStatus(groupId: circle.id, actingPeerId: admin.peerId, peerId: owner.peerId, newStatus: MemberStatus.suspended),
        throwsA(isA<PermissionException>()),
      );
    });

    test('suspended admin cannot act', () async {
      await groups.updateMemberStatus(groupId: circle.id, actingPeerId: owner.peerId, peerId: admin.peerId, newStatus: MemberStatus.suspended);
      expect(
        () => txs.createTransaction(
          groupId: circle.id, authorPeerId: admin.peerId, authorKeyPair: admin.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 50),
        throwsA(isA<PermissionException>()),
      );
    });

    test('every roster change bumps the sequence number', () async {
      final before = (await groups.getGroup(circle.id))!.sequenceNumber;
      await groups.updateMemberRole(groupId: circle.id, actingPeerId: owner.peerId, peerId: member.peerId, newRole: MemberRole.admin);
      await groups.updateMemberStatus(groupId: circle.id, actingPeerId: owner.peerId, peerId: member.peerId, newStatus: MemberStatus.suspended);
      expect((await groups.getGroup(circle.id))!.sequenceNumber, before + 2);
    });
  });

  group('Transactions & sequences (§19)', () {
    test('sequence numbers are per author, so two admins never collide', () async {
      Future<Transaction> record(Person who) => txs.createTransaction(
          groupId: circle.id, authorPeerId: who.peerId, authorKeyPair: who.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 10);
      final a1 = await record(owner);
      final b1 = await record(admin);
      final a2 = await record(owner);
      expect([a1.sequenceNumber, a2.sequenceNumber], [1, 2]);
      expect(b1.sequenceNumber, 1);
    });

    test('importRemote verifies the author signature and dedups', () async {
      final tx = await txs.createTransaction(
          groupId: circle.id, authorPeerId: admin.peerId, authorKeyPair: admin.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 50);
      expect(await txs.importRemote(tx, authorPublicKey: admin.pub, cid: 'c1'), TransactionService.importedDuplicate);
      expect(() => txs.importRemote(tx, authorPublicKey: outsider.pub, cid: 'c1'), throwsA(isA<StateError>()));
    });

    test('balances move and reversal undoes them', () async {
      final tx = await txs.createTransaction(
          groupId: circle.id, authorPeerId: admin.peerId, authorKeyPair: admin.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 50);
      final r = await gov.requestReversal(
          groupId: circle.id, actingPeerId: member.peerId, actingKeyPair: member.kp, transactionId: tx.id, reason: 'dup');
      // requester may not decide their own request
      expect(
        () => gov.decideReversal(groupId: circle.id, actingPeerId: member.peerId, actingKeyPair: member.kp, reversalId: r.id, approve: true),
        throwsA(isA<PermissionException>()),
      );
      await gov.decideReversal(groupId: circle.id, actingPeerId: owner.peerId, actingKeyPair: owner.kp, reversalId: r.id, approve: true);
      expect((await txs.getById(tx.id))!.status, TransactionStatus.reversed);
    });
  });

  group('Snapshots (§9/§19)', () {
    test('signed snapshot round-trips and a member cannot publish', () async {
      final snap = await groups.buildSnapshot(circle.id, publisherPeerId: admin.peerId, publisherKeyPair: admin.kp);
      expect(snap['signature'], isNotEmpty);
      expect(
        () => groups.buildSnapshot(circle.id, publisherPeerId: member.peerId, publisherKeyPair: member.kp),
        throwsA(isA<PermissionException>()),
      );
      // Our own snapshot echoed back: same sequence + timestamp → verified but not re-applied.
      final result = await groups.importSnapshot(snap, cid: 'cid1', ownPeerId: admin.peerId);
      expect(result.applied, isFalse);
      expect(result.reason, contains('up to date'));
      expect(result.group.cid, 'cid1');
    });

    test('tampered snapshot is rejected', () async {
      final snap = await groups.buildSnapshot(circle.id, publisherPeerId: owner.peerId, publisherKeyPair: owner.kp);
      final tampered = Map<String, dynamic>.from(snap);
      final g = Map<String, dynamic>.from(tampered['group'] as Map);
      g['name'] = 'Evil';
      tampered['group'] = g;
      expect(() => groups.importSnapshot(tampered), throwsA(isA<StateError>()));
    });

    test('snapshot published by a non-admin is rejected', () async {
      // Build a syntactically valid snapshot signed by the member.
      final snap = await groups.buildSnapshot(circle.id, publisherPeerId: owner.peerId, publisherKeyPair: owner.kp);
      final forged = Map<String, dynamic>.from(snap)..remove('signature');
      forged['publisher'] = member.peerId;
      final sig = await SigningService.sign(
        GroupServiceTestHook.signingBytes(forged), member.kp);
      forged['signature'] = sig.bytes;
      expect(() => groups.importSnapshot(forged), throwsA(isA<StateError>()));
    });

    test('older snapshot does not overwrite newer local state', () async {
      final old = await groups.buildSnapshot(circle.id, publisherPeerId: owner.peerId, publisherKeyPair: owner.kp);
      await groups.updateMemberRole(groupId: circle.id, actingPeerId: owner.peerId, peerId: member.peerId, newRole: MemberRole.admin);
      final result = await groups.importSnapshot(old, ownPeerId: owner.peerId);
      expect(result.applied, isFalse);
      expect((await groups.getMember(circle.id, member.peerId))!.role, MemberRole.admin);
    });

    test('join bootstrap: initial snapshot must be signed by the owner', () async {
      final snap = await groups.buildSnapshot(circle.id, publisherPeerId: admin.peerId, publisherKeyPair: admin.kp);
      // Simulate a fresh device: wipe the local group.
      await closeTestDatabase();
      await useInMemoryDatabase();
      final fresh = GroupService(groupKeyService: GroupKeyService(), inviteService: InviteService());
      expect(() => fresh.importSnapshot(snap, ownPeerId: outsider.peerId), throwsA(isA<StateError>()));
    });
  });

  group('Invites (§16)', () {
    test('one-use, expiry and nonce are enforced', () async {
      final inv = await invites.createInvite(
          groupId: circle.id, groupCid: 'cid', inviterPeerId: admin.peerId, inviterKeyPair: admin.kp);
      await InviteService.verify(inv, groupId: circle.id, presentedNonce: inv.nonce!, inviterPublicKey: admin.pub);

      expect(
        () => InviteService.verify(inv, groupId: circle.id, presentedNonce: Uint8List(16), inviterPublicKey: admin.pub),
        throwsA(isA<InviteException>()),
      );
      expect(
        () => InviteService.verify(inv, groupId: circle.id, presentedNonce: inv.nonce!, inviterPublicKey: member.pub),
        throwsA(isA<InviteException>()),
      );
      expect(
        () => InviteService.verify(inv, groupId: circle.id, presentedNonce: inv.nonce!, inviterPublicKey: admin.pub,
            now: inv.expiresAt.add(const Duration(minutes: 1))),
        throwsA(isA<InviteException>()),
      );
      await invites.markUsed(inv.id, outsider.peerId);
      final used = (await invites.getById(inv.id))!;
      expect(
        () => InviteService.verify(used, groupId: circle.id, presentedNonce: inv.nonce!, inviterPublicKey: admin.pub),
        throwsA(isA<InviteException>()),
      );
    });

    test('used flag survives a snapshot merge but never reverts', () async {
      final inv = await invites.createInvite(
          groupId: circle.id, groupCid: 'cid', inviterPeerId: admin.peerId, inviterKeyPair: admin.kp);
      await invites.markUsed(inv.id, outsider.peerId);
      final stale = InviteData(
        id: inv.id, groupId: inv.groupId, createdAt: inv.createdAt, expiresAt: inv.expiresAt, used: false,
        nonce: inv.nonce, inviterPeerId: inv.inviterPeerId, inviterSignature: inv.inviterSignature);
      await invites.mergeFromSnapshot([stale]);
      expect((await invites.getById(inv.id))!.used, isTrue);
    });
  });

  group('Loan lifecycle (§15)', () {
    Future<void> contribute(Person who, int times) async {
      for (var i = 0; i < times; i++) {
        await txs.createTransaction(
            groupId: circle.id, authorPeerId: admin.peerId, authorKeyPair: admin.kp,
            fromPeerId: who.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 50);
      }
    }

    test('eligibility: min contributions and max multiplier', () async {
      expect(await loans.eligibilityProblems(groupId: circle.id, borrowerPeerId: member.peerId, requestedAmount: 10),
          contains(startsWith('At least 2 contributions')));
      await contribute(member, 2);
      expect(await loans.eligibilityProblems(groupId: circle.id, borrowerPeerId: member.peerId, requestedAmount: 300), isEmpty);
      expect(await loans.eligibilityProblems(groupId: circle.id, borrowerPeerId: member.peerId, requestedAmount: 301),
          contains(startsWith('Maximum loan')));
      expect(await loans.eligibilityProblems(groupId: circle.id, borrowerPeerId: outsider.peerId, requestedAmount: 10),
          contains('Only active members can request loans'));
    });

    test('request → approve → disburse → repay → completed', () async {
      await contribute(member, 2);
      var loan = await loans.requestLoan(
          groupId: circle.id, borrowerPeerId: member.peerId, borrowerKeyPair: member.kp, requestedAmount: 200, termWeeks: 4);
      expect(loan.status, LoanStatus.pending); // requireLoanApproval defaults to true
      expect(await loans.verifyRequestSignature(loan, member.pub), isTrue);

      // borrower cannot approve; member cannot approve; admin can
      expect(() => loans.approveLoan(loanId: loan.id, approvedAmount: 200, approverPeerId: member.peerId, approverKeyPair: member.kp),
          throwsA(isA<LoanAuthorizationException>()));
      loan = await loans.approveLoan(loanId: loan.id, approvedAmount: 200, approverPeerId: admin.peerId, approverKeyPair: admin.kp);
      expect(loan.status, LoanStatus.approved);
      expect(await loans.verifyApprovalSignature(loan, admin.pub), isTrue);

      loan = await loans.disburseLoan(loanId: loan.id, adminPeerId: admin.peerId, adminKeyPair: admin.kp);
      expect(loan.status, LoanStatus.disbursed);
      final schedule = await loans.schedule(loan.id);
      expect(schedule.length, 4);
      final total = schedule.fold<double>(0, (s, i) => s + i.expectedAmount);
      expect(total, closeTo(220, 0.001)); // 200 × 1.10
      expect((await groups.getMember(circle.id, member.peerId))!.hasOutstandingLoan, isTrue);
      final loanTx = (await txs.getByLoanId(loan.id)).single;
      expect(loanTx.type, TransactionType.loan);
      expect(loanTx.toPeerId, member.peerId);

      // a second loan while one is open is refused
      expect(await loans.eligibilityProblems(groupId: circle.id, borrowerPeerId: member.peerId, requestedAmount: 10),
          contains('You already have an open loan'));

      loan = await loans.recordRepayment(loanId: loan.id, adminPeerId: admin.peerId, adminKeyPair: admin.kp, amount: 55);
      expect(loan.status, LoanStatus.repaying);
      expect((await loans.schedule(loan.id)).first.isPaid, isTrue);

      loan = await loans.recordRepayment(loanId: loan.id, adminPeerId: admin.peerId, adminKeyPair: admin.kp, amount: 165);
      expect(loan.status, LoanStatus.completed);
      expect((await groups.getMember(circle.id, member.peerId))!.hasOutstandingLoan, isFalse);
    });

    test('auto-approval when the group does not require it', () async {
      await groups.updateGroupConfig(
        groupId: circle.id, actingPeerId: owner.peerId,
        config: const GroupConfig(groupId: '', contributionAmount: 50, minContributionsForLoan: 0, requireLoanApproval: false),
      );
      await contribute(member, 1);
      final loan = await loans.requestLoan(
          groupId: circle.id, borrowerPeerId: member.peerId, borrowerKeyPair: member.kp, requestedAmount: 20, termWeeks: 1);
      expect(loan.status, LoanStatus.approved);
      expect(loan.approvedByPeerId, member.peerId);
    });

    test('dissolution is blocked while a loan is open', () async {
      await contribute(member, 2);
      final loan = await loans.requestLoan(
          groupId: circle.id, borrowerPeerId: member.peerId, borrowerKeyPair: member.kp, requestedAmount: 100, termWeeks: 2);
      await loans.approveLoan(loanId: loan.id, approvedAmount: 100, approverPeerId: admin.peerId, approverKeyPair: admin.kp);
      await loans.disburseLoan(loanId: loan.id, adminPeerId: admin.peerId, adminKeyPair: admin.kp);
      expect(await gov.dissolutionBlockers(circle.id), isNotEmpty);
      expect(() => gov.dissolveGroup(groupId: circle.id, actingPeerId: owner.peerId, actingKeyPair: owner.kp),
          throwsA(isA<PermissionException>()));
    });

    test('dissolution pays out net balances and freezes the group', () async {
      await contribute(member, 2);
      final paid = await gov.dissolveGroup(groupId: circle.id, actingPeerId: owner.peerId, actingKeyPair: owner.kp);
      expect(paid.single.toPeerId, member.peerId);
      expect(paid.single.amount, 100);
      expect((await groups.getGroup(circle.id))!.status, GroupStatus.dissolved);
      expect(
        () => txs.createTransaction(
          groupId: circle.id, authorPeerId: admin.peerId, authorKeyPair: admin.kp,
          fromPeerId: member.peerId, toPeerId: 'group', type: TransactionType.contribution, amount: 50),
        throwsA(anything),
      );
    });
  });
}

/// Exposes the snapshot signing bytes for the forgery test.
class GroupServiceTestHook {
  static List<int> signingBytes(Map<String, dynamic> body) => GroupService.snapshotSigningBytes(body);
}
