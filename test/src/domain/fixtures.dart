import 'dart:typed_data';

import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';

/// Shared builders for domain tests. Every builder takes the identity fields
/// and fills the rest with fixed, valid defaults so tests only spell out
/// what they exercise.
///
/// Three signature bytes; content never matters in domain tests.
Uint8List testSignature() => Uint8List.fromList(const [1, 2, 3]);

/// A valid member; override rank or standing via [role] and [status].
Member testMember(
  String peerId, {
  String name = 'Test Member',
  MemberRole role = MemberRole.member,
  MemberStatus status = MemberStatus.active,
}) =>
    Member(
      peerId: peerId,
      name: name,
      role: role,
      joinedAt: DateTime.utc(2026, 1, 5),
      publicKey: testSignature(),
      status: status,
    );

/// A valid group with [members].
Group testGroup(
  String id, {
  List<Member> members = const [],
  int sequenceNumber = 0,
}) =>
    Group(
      id: id,
      name: 'Test Group',
      config: GroupConfig(groupId: id, contributionAmount: 100),
      members: members,
      createdAt: DateTime.utc(2026, 1, 5),
      sequenceNumber: sequenceNumber,
      ownerSignature: testSignature(),
    );

/// A valid transaction; override kind and money via [type] and [amount].
Transaction testTransaction(
  String id, {
  String groupId = 'g-1',
  String fromPeerId = 'alice',
  String toPeerId = 'group',
  TransactionType type = TransactionType.contribution,
  double amount = 100,
  int sequenceNumber = 1,
  String? loanId,
}) =>
    Transaction(
      id: id,
      groupId: groupId,
      fromPeerId: fromPeerId,
      toPeerId: toPeerId,
      type: type,
      amount: amount,
      timestamp: DateTime.utc(2026, 2, 1, 10),
      sequenceNumber: sequenceNumber,
      senderSignature: testSignature(),
      loanId: loanId,
    );

/// A valid loan request; override state via [status] and [approvedAmount].
LoanRequest testLoan(
  String id, {
  String borrowerPeerId = 'alice',
  double requestedAmount = 300,
  double approvedAmount = 0,
  LoanStatus status = LoanStatus.pending,
}) =>
    LoanRequest(
      id: id,
      groupId: 'g-1',
      borrowerPeerId: borrowerPeerId,
      requestedAmount: requestedAmount,
      approvedAmount: approvedAmount,
      interestRate: 0.10,
      termWeeks: 4,
      status: status,
      requestedAt: DateTime.utc(2026, 2, 1),
      borrowerSignature: testSignature(),
    );

/// A valid meeting with the given attendance.
Meeting testMeeting(String id, {List<Attendance> attendance = const []}) =>
    Meeting(
      id: id,
      groupId: 'g-1',
      scheduledAt: DateTime.utc(2026, 3, 7, 9),
      attendance: attendance,
    );
