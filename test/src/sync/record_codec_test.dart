import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/invites.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/sync/record_codec.dart';

import '../domain/fixtures.dart';

void main() {
  group('RecordCodec', () {
    test('transactions survive the wire', () {
      final Transaction tx = testTransaction(
        't',
        type: TransactionType.repayment,
        loanId: 'l-1',
      );

      expect(
        RecordCodec.transactionFromJson(RecordCodec.transactionToJson(tx)),
        tx,
      );
    });

    test('reversals survive the wire', () {
      final TransactionReversal r = TransactionReversal(
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
        RecordCodec.reversalFromJson(RecordCodec.reversalToJson(r)),
        r,
      );
    });

    test('loans survive the wire', () {
      final LoanRequest loan = testLoan(
        'l',
        approvedAmount: 300,
        status: LoanStatus.repaying,
      ).copyWith(
        approvedAt: DateTime.utc(2026, 2, 2),
        approvedByPeerId: 'owner',
        disbursedAt: DateTime.utc(2026, 2, 3),
        approverSignature: testSignature(),
      );

      expect(RecordCodec.loanFromJson(RecordCodec.loanToJson(loan)), loan);
    });

    test('meetings survive the wire', () {
      final Meeting m = testMeeting(
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

      expect(RecordCodec.meetingFromJson(RecordCodec.meetingToJson(m)), m);
    });

    test('members and groups survive the wire', () {
      final Group group = testGroup(
        'g',
        members: [
          testMember('o', role: MemberRole.owner),
          testMember('m', status: MemberStatus.suspended),
        ],
        sequenceNumber: 7,
      ).copyWith(cid: () => 'cid-1');

      final Group back = RecordCodec.groupFromJson(
        RecordCodec.groupToJson(group),
      );

      // Snapshots carry no local CID.
      expect(back, group.copyWith(cid: () => null));
      expect(
        RecordCodec.memberFromJson(
          RecordCodec.memberToJson(testMember('m')),
        ),
        testMember('m'),
      );
    });

    test('snapshot invites use the legacy shape', () {
      final Invite invite = Invite(
        id: 'i',
        groupId: 'g',
        groupCid: 'cid',
        groupTopic: 'vbank/group/g',
        inviterPeerId: 'a',
        inviterName: 'A',
        wrappedKey: Uint8List.fromList([9]),
        createdAt: DateTime.utc(2026, 4, 1),
        expiresAt: DateTime.utc(2026, 4, 8),
        used: true,
        usedByPeerId: 'b',
        nonce: Uint8List.fromList([7]),
        inviterSignature: testSignature(),
      );
      final Map<String, dynamic> json = RecordCodec.inviteToSnapshotJson(
        invite,
      );

      expect(json['cid'], 'cid');
      expect(json['inviter'], 'a');
      final Invite back = RecordCodec.inviteFromSnapshotJson(json);

      expect(back.used, isTrue);
      expect(back.usedByPeerId, 'b');
      expect(back.wrappedKey, Uint8List.fromList([9]));
      expect(back.groupTopic, isNull);
    });

    test('governance records survive the wire', () {
      final MemberRemoval removal = MemberRemoval(
        id: 'r',
        groupId: 'g',
        removedPeerId: 'b',
        removedByPeerId: 'a',
        reason: 'why',
        action: RemovalAction.remove,
        removedAt: DateTime.utc(2026, 5, 1),
        adminSignature: testSignature(),
      );
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
      );

      expect(
        RecordCodec.removalFromJson(RecordCodec.removalToJson(removal)),
        removal,
      );
      expect(
        RecordCodec.transferFromJson(RecordCodec.transferToJson(transfer)),
        transfer,
      );
      expect(
        RecordCodec.dissolutionFromJson(
          RecordCodec.dissolutionToJson(dissolution),
        ),
        dissolution,
      );
    });

    test('binary fields accept byte strings, lists and base64', () {
      final Transaction tx = testTransaction('t');
      final Map<String, dynamic> asJson = RecordCodec.transactionToJson(tx);
      final Map<String, dynamic> asLists = {
        ...asJson,
        'senderSignature': List<int>.from(tx.senderSignature),
      };
      final Map<String, dynamic> asB64 = {
        ...asJson,
        'senderSignature': base64Encode(tx.senderSignature),
      };

      expect(RecordCodec.transactionFromJson(asLists), tx);
      expect(RecordCodec.transactionFromJson(asB64), tx);
    });

    test('malformed records throw instead of guessing', () {
      expect(
        () => RecordCodec.transactionFromJson(const {'id': 't'}),
        throwsA(isA<Object>()),
      );
      expect(
        () => RecordCodec.transactionFromJson(
          RecordCodec.transactionToJson(testTransaction('t'))
            ..['type'] = 'teleport',
        ),
        throwsA(isA<Object>()),
      );
      expect(
        () => RecordCodec.loanFromJson(const {'id': 'l'}),
        throwsA(isA<Object>()),
      );
      expect(
        () => RecordCodec.meetingFromJson(const {'id': 'm'}),
        throwsA(isA<Object>()),
      );
      expect(
        () => RecordCodec.groupFromJson(const {'id': 'g'}),
        throwsA(isA<Object>()),
      );
      expect(
        () => RecordCodec.configFromJson(const {'groupId': 'g'}),
        throwsA(isA<Object>()),
      );
    });
  });
}
