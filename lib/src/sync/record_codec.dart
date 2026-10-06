import 'dart:convert';
import 'dart:typed_data';

import '../domain/core/result.dart';
import '../domain/governance.dart';
import '../domain/group.dart';
import '../domain/invites.dart';
import '../domain/loans.dart';
import '../domain/meeting_time.dart';
import '../domain/meetings.dart';
import '../domain/membership.dart';
import '../domain/transactions.dart';

/// Entities to and from the legacy JSON record shapes.
///
/// These maps ride inside [SyncEnvelope] payloads and snapshot bodies. Field
/// names and value shapes are byte-identical to the legacy app, so old and
/// rewritten nodes read each other's records. Parsing is strict: malformed
/// records throw [FormatException] and the apply pipeline rejects them
/// instead of guessing.
///
/// Binary fields accept CBOR byte strings (`Uint8List`), plain lists and
/// base64 strings (v1); they encode as byte strings.
abstract final class RecordCodec {
  /// Decodes bytes that may be a byte string, a list or base64.
  static Uint8List bytes(Object? v) {
    if (v is Uint8List) {
      return v;
    }
    if (v is String) {
      return Uint8List.fromList(base64Decode(v));
    }
    return Uint8List.fromList((v as List).cast<int>());
  }

  /// Parses an ISO instant, accepting anything [DateTime.parse] takes.
  static DateTime instant(Object? v) => DateTime.parse(v as String);

  /// Parses an enum by name, throwing on unknown values.
  static T enumeration<T extends Enum>(Object? v, List<T> values) =>
      values.byName(v as String);

  // ---------------------------------------------------------- transactions --

  /// Serializes a transaction to its record shape.
  static Map<String, dynamic> transactionToJson(Transaction tx) => {
        'id': tx.id,
        'groupId': tx.groupId,
        'fromPeerId': tx.fromPeerId,
        'toPeerId': tx.toPeerId,
        'type': tx.type.name,
        'amount': tx.amount,
        'currency': tx.currency,
        'note': tx.note,
        'timestamp': tx.timestamp.toIso8601String(),
        'sequenceNumber': tx.sequenceNumber,
        'senderSignature': Uint8List.fromList(tx.senderSignature),
        'status': tx.status.name,
        'authorPeerId': tx.authorPeerId,
        'loanId': tx.loanId,
      };

  /// Parses a transaction record.
  static Transaction transactionFromJson(Map<String, dynamic> json) =>
      Transaction(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        fromPeerId: json['fromPeerId'] as String,
        toPeerId: json['toPeerId'] as String,
        type: enumeration(json['type'], TransactionType.values),
        amount: (json['amount'] as num).toDouble(),
        currency: json['currency'] as String? ?? 'ZMW',
        note: json['note'] as String?,
        timestamp: instant(json['timestamp']),
        sequenceNumber: json['sequenceNumber'] as int,
        senderSignature: bytes(json['senderSignature']),
        status: enumeration(
          json['status'] ?? 'confirmed',
          TransactionStatus.values,
        ),
        authorPeerId: json['authorPeerId'] as String?,
        loanId: json['loanId'] as String?,
      );

  /// Serializes a reversal request or decision.
  static Map<String, dynamic> reversalToJson(TransactionReversal r) => {
        'id': r.id,
        'originalTransactionId': r.originalTransactionId,
        'groupId': r.groupId,
        'requestedByPeerId': r.requestedByPeerId,
        'approvedByPeerId': r.approvedByPeerId,
        'reason': r.reason,
        'status': r.status.name,
        'requestedAt': r.requestedAt.toIso8601String(),
        'resolvedAt': r.resolvedAt?.toIso8601String(),
        'requesterSignature': Uint8List.fromList(r.requesterSignature),
        'approverSignature': r.approverSignature == null
            ? null
            : Uint8List.fromList(r.approverSignature!),
      };

  /// Parses a reversal record.
  static TransactionReversal reversalFromJson(Map<String, dynamic> json) =>
      TransactionReversal(
        id: json['id'] as String,
        originalTransactionId: json['originalTransactionId'] as String,
        groupId: json['groupId'] as String,
        requestedByPeerId: json['requestedByPeerId'] as String,
        approvedByPeerId: json['approvedByPeerId'] as String?,
        reason: json['reason'] as String,
        status: enumeration(json['status'], ReversalStatus.values),
        requestedAt: instant(json['requestedAt']),
        resolvedAt: json['resolvedAt'] == null
            ? null
            : instant(json['resolvedAt']),
        requesterSignature: bytes(json['requesterSignature']),
        approverSignature: json['approverSignature'] == null
            ? null
            : bytes(json['approverSignature']),
      );

  // ---------------------------------------------------------------- loans --

  /// Serializes a loan request or decision.
  static Map<String, dynamic> loanToJson(LoanRequest loan) => {
        'id': loan.id,
        'groupId': loan.groupId,
        'borrowerPeerId': loan.borrowerPeerId,
        'requestedAmount': loan.requestedAmount,
        'approvedAmount': loan.approvedAmount,
        'interestRate': loan.interestRate,
        'termWeeks': loan.termWeeks,
        'reason': loan.reason,
        'status': loan.status.name,
        'requestedAt': loan.requestedAt.toIso8601String(),
        'approvedAt': loan.approvedAt?.toIso8601String(),
        'approvedByPeerId': loan.approvedByPeerId,
        'disbursedAt': loan.disbursedAt?.toIso8601String(),
        'completedAt': loan.completedAt?.toIso8601String(),
        'defaultedAt': loan.defaultedAt?.toIso8601String(),
        'borrowerSignature': Uint8List.fromList(loan.borrowerSignature),
        'approverSignature': loan.approverSignature == null
            ? null
            : Uint8List.fromList(loan.approverSignature!),
      };

  /// Parses a loan record.
  static LoanRequest loanFromJson(Map<String, dynamic> json) => LoanRequest(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        borrowerPeerId: json['borrowerPeerId'] as String,
        requestedAmount: (json['requestedAmount'] as num).toDouble(),
        approvedAmount: (json['approvedAmount'] as num?)?.toDouble() ?? 0,
        interestRate: (json['interestRate'] as num).toDouble(),
        termWeeks: json['termWeeks'] as int,
        reason: json['reason'] as String?,
        status: enumeration(json['status'] ?? 'pending', LoanStatus.values),
        requestedAt: instant(json['requestedAt']),
        approvedAt: json['approvedAt'] == null
            ? null
            : instant(json['approvedAt']),
        approvedByPeerId: json['approvedByPeerId'] as String?,
        disbursedAt: json['disbursedAt'] == null
            ? null
            : instant(json['disbursedAt']),
        completedAt: json['completedAt'] == null
            ? null
            : instant(json['completedAt']),
        defaultedAt: json['defaultedAt'] == null
            ? null
            : instant(json['defaultedAt']),
        borrowerSignature: bytes(json['borrowerSignature']),
        approverSignature: json['approverSignature'] == null
            ? null
            : bytes(json['approverSignature']),
      );

  // --------------------------------------------------------------- meetings --

  /// Serializes a meeting with its attendance sheet.
  static Map<String, dynamic> meetingToJson(Meeting meeting) => {
        'id': meeting.id,
        'groupId': meeting.groupId,
        'scheduledAt': meeting.scheduledAt.toIso8601String(),
        'status': meeting.status.name,
        'attendance': [
          for (final Attendance a in meeting.attendance)
            {
              'peerId': a.peerId,
              'status': a.status.name,
              'contributed': a.contributed,
              'contributionTime': a.contributionTime?.toIso8601String(),
            },
        ],
        'notes': meeting.notes,
        'totalCollected': meeting.totalCollected,
        'completedAt': meeting.completedAt?.toIso8601String(),
      };

  /// Parses a meeting record.
  static Meeting meetingFromJson(Map<String, dynamic> json) => Meeting(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        scheduledAt: instant(json['scheduledAt']),
        status: enumeration(
          json['status'] ?? 'scheduled',
          MeetingStatus.values,
        ),
        attendance: [
          for (final Object? a in (json['attendance'] as List?) ?? const [])
            _attendanceFromJson((a as Map).cast<String, dynamic>()),
        ],
        notes: json['notes'] as String?,
        totalCollected: (json['totalCollected'] as num?)?.toDouble() ?? 0,
        completedAt: json['completedAt'] == null
            ? null
            : instant(json['completedAt']),
      );

  /// Parses one attendance record.
  static Attendance _attendanceFromJson(Map<String, dynamic> json) =>
      Attendance(
        peerId: json['peerId'] as String,
        status: enumeration(
          json['status'] ?? 'absent',
          MeetingAttendanceStatus.values,
        ),
        contributed: json['contributed'] as bool? ?? false,
        contributionTime: json['contributionTime'] == null
            ? null
            : instant(json['contributionTime']),
      );

  // --------------------------------------------------------------- members --

  /// Serializes a roster member.
  static Map<String, dynamic> memberToJson(Member member) => {
        'peerId': member.peerId,
        'name': member.name,
        'role': member.role.name,
        'joinedAt': member.joinedAt.toIso8601String(),
        'publicKey': Uint8List.fromList(member.publicKey),
        'status': member.status.name,
        'hasOutstandingLoan': member.hasOutstandingLoan,
        if (member.encKey != null)
          'encKey': Uint8List.fromList(member.encKey!),
      };

  /// Parses a roster member.
  static Member memberFromJson(Map<String, dynamic> json) => Member(
        peerId: json['peerId'] as String,
        name: json['name'] as String,
        role: enumeration(json['role'] ?? 'member', MemberRole.values),
        joinedAt: instant(json['joinedAt']),
        publicKey: bytes(json['publicKey']),
        status: enumeration(json['status'] ?? 'active', MemberStatus.values),
        hasOutstandingLoan: json['hasOutstandingLoan'] as bool? ?? false,
        encKey: json['encKey'] == null ? null : bytes(json['encKey']),
      );

  // ----------------------------------------------------------------- group --

  /// Serializes group rules.
  static Map<String, dynamic> configToJson(GroupConfig config) => {
        'groupId': config.groupId,
        'contributionAmount': config.contributionAmount,
        'frequency': config.frequency.name,
        'meetingDayOfWeek': config.meetingDayOfWeek,
        'meetingTime': config.meetingTime.format(),
        'maxLoanMultiplier': config.maxLoanMultiplier,
        'loanInterestRate': config.loanInterestRate,
        'latePenaltyRate': config.latePenaltyRate,
        'minContributionsForLoan': config.minContributionsForLoan,
        'currency': config.currency,
        'savingsTarget': config.savingsTarget,
        'requireLoanApproval': config.requireLoanApproval,
      };

  /// Parses group rules.
  static GroupConfig configFromJson(Map<String, dynamic> json) {
    final Result<MeetingTime> time = MeetingTime.parse(
      json['meetingTime'] as String? ?? '09:00',
    );
    if (time.isErr) {
      throw const FormatException('bad meetingTime');
    }
    return GroupConfig(
      groupId: json['groupId'] as String,
      contributionAmount: (json['contributionAmount'] as num).toDouble(),
      frequency: enumeration(
        json['frequency'] ?? 'monthly',
        ContributionFrequency.values,
      ),
      meetingDayOfWeek: json['meetingDayOfWeek'] as int? ?? 0,
      meetingTime: time.value,
      maxLoanMultiplier: (json['maxLoanMultiplier'] as num?)?.toDouble() ?? 3,
      loanInterestRate: (json['loanInterestRate'] as num?)?.toDouble() ?? 0.1,
      latePenaltyRate: (json['latePenaltyRate'] as num?)?.toDouble() ?? 0.05,
      minContributionsForLoan: json['minContributionsForLoan'] as int? ?? 3,
      currency: json['currency'] as String? ?? 'ZMW',
      savingsTarget: (json['savingsTarget'] as num?)?.toDouble(),
      requireLoanApproval: json['requireLoanApproval'] as bool? ?? true,
    );
  }

  /// Serializes a group (snapshot form: no local CID).
  static Map<String, dynamic> groupToJson(Group group) => {
        'id': group.id,
        'name': group.name,
        'config': configToJson(group.config),
        'members': [
          for (final Member m in group.members) memberToJson(m),
        ],
        'inviteCids': group.inviteCids,
        'requireApproval': group.requireApproval,
        'createdAt': group.createdAt.toIso8601String(),
        'sequenceNumber': group.sequenceNumber,
        'status': group.status.name,
        'ownerSignature': Uint8List.fromList(group.ownerSignature),
      };

  /// Parses a group snapshot.
  static Group groupFromJson(Map<String, dynamic> json) => Group(
        id: json['id'] as String,
        name: json['name'] as String,
        config: configFromJson(json['config'] as Map<String, dynamic>),
        members: [
          for (final Object? m in (json['members'] as List?) ?? const [])
            memberFromJson((m as Map).cast<String, dynamic>()),
        ],
        inviteCids:
            ((json['inviteCids'] as List?) ?? const []).cast<String>(),
        requireApproval: json['requireApproval'] as bool? ?? false,
        createdAt: instant(json['createdAt']),
        sequenceNumber: json['sequenceNumber'] as int? ?? 0,
        status: enumeration(json['status'] ?? 'active', GroupStatus.values),
        ownerSignature: bytes(json['ownerSignature']),
      );

  // ---------------------------------------------------------------- invites --

  /// Serializes an invite to the snapshot shape (legacy form: no topic or
  /// inviter name on the wire; links and the roster supply those).
  static Map<String, dynamic> inviteToSnapshotJson(Invite invite) => {
        'id': invite.id,
        'groupId': invite.groupId,
        'cid': invite.groupCid,
        'used': invite.used,
        'usedBy': invite.usedByPeerId,
        'createdAt': invite.createdAt.toIso8601String(),
        'expiresAt': invite.expiresAt.toIso8601String(),
        'nonce': base64Encode(invite.nonce),
        'inviter': invite.inviterPeerId,
        'signature': base64Encode(invite.inviterSignature),
        'wrappedKey': invite.wrappedKey == null
            ? null
            : base64Encode(invite.wrappedKey!),
      };

  /// Parses a snapshot invite. Topic and inviter name are link-local and
  /// stay null here.
  static Invite inviteFromSnapshotJson(Map<String, dynamic> json) => Invite(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        groupCid: json['cid'] as String? ?? '',
        groupTopic: null,
        inviterPeerId: json['inviter'] as String? ?? '',
        inviterName: null,
        wrappedKey: json['wrappedKey'] == null
            ? null
            : Uint8List.fromList(base64Decode(json['wrappedKey'] as String)),
        createdAt: instant(json['createdAt']),
        expiresAt: instant(json['expiresAt']),
        used: json['used'] as bool? ?? false,
        usedByPeerId: json['usedBy'] as String?,
        nonce: json['nonce'] == null
            ? Uint8List(0)
            : Uint8List.fromList(base64Decode(json['nonce'] as String)),
        inviterSignature: json['signature'] == null
            ? Uint8List(0)
            : Uint8List.fromList(
                base64Decode(json['signature'] as String),
              ),
      );

  // ------------------------------------------------------------- governance --

  /// Serializes a removal record.
  static Map<String, dynamic> removalToJson(MemberRemoval removal) => {
        'id': removal.id,
        'groupId': removal.groupId,
        'removedPeerId': removal.removedPeerId,
        'removedByPeerId': removal.removedByPeerId,
        'reason': removal.reason,
        'hasOutstandingLoan': removal.hasOutstandingLoan,
        'outstandingAmount': removal.outstandingAmount,
        'action': removal.action.name,
        'removedAt': removal.removedAt.toIso8601String(),
        'adminSignature': Uint8List.fromList(removal.adminSignature),
        'lifted': removal.lifted,
      };

  /// Parses a removal record.
  static MemberRemoval removalFromJson(Map<String, dynamic> json) =>
      MemberRemoval(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        removedPeerId: json['removedPeerId'] as String,
        removedByPeerId: json['removedByPeerId'] as String,
        reason: json['reason'] as String,
        hasOutstandingLoan: json['hasOutstandingLoan'] as bool? ?? false,
        outstandingAmount:
            (json['outstandingAmount'] as num?)?.toDouble() ?? 0,
        action: enumeration(json['action'], RemovalAction.values),
        removedAt: instant(json['removedAt']),
        adminSignature: bytes(json['adminSignature']),
        lifted: json['lifted'] as bool? ?? false,
      );

  /// Serializes an ownership transfer.
  static Map<String, dynamic> transferToJson(OwnershipTransfer transfer) => {
        'id': transfer.id,
        'groupId': transfer.groupId,
        'fromPeerId': transfer.fromPeerId,
        'toPeerId': transfer.toPeerId,
        'transferredAt': transfer.transferredAt.toIso8601String(),
        'oldOwnerSignature': Uint8List.fromList(transfer.oldOwnerSignature),
        'newOwnerSignature': Uint8List.fromList(transfer.newOwnerSignature),
      };

  /// Parses an ownership transfer.
  static OwnershipTransfer transferFromJson(Map<String, dynamic> json) =>
      OwnershipTransfer(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        fromPeerId: json['fromPeerId'] as String,
        toPeerId: json['toPeerId'] as String,
        transferredAt: instant(json['transferredAt']),
        oldOwnerSignature: bytes(json['oldOwnerSignature']),
        newOwnerSignature: bytes(json['newOwnerSignature']),
      );

  /// Serializes a dissolution record.
  static Map<String, dynamic> dissolutionToJson(GroupDissolution d) => {
        'id': d.id,
        'groupId': d.groupId,
        'initiatedByPeerId': d.initiatedByPeerId,
        'initiatedAt': d.initiatedAt.toIso8601String(),
        'status': d.status.name,
        'allLoansSettled': d.allLoansSettled,
        'fundsDistributed': d.fundsDistributed,
        'completedAt': d.completedAt?.toIso8601String(),
      };

  /// Parses a dissolution record.
  static GroupDissolution dissolutionFromJson(Map<String, dynamic> json) =>
      GroupDissolution(
        id: json['id'] as String,
        groupId: json['groupId'] as String,
        initiatedByPeerId: json['initiatedByPeerId'] as String,
        initiatedAt: instant(json['initiatedAt']),
        status: enumeration(
          json['status'] ?? 'initiating',
          DissolutionStatus.values,
        ),
        allLoansSettled: json['allLoansSettled'] as bool? ?? false,
        fundsDistributed: json['fundsDistributed'] as bool? ?? false,
        completedAt: json['completedAt'] == null
            ? null
            : instant(json['completedAt']),
      );

}

// Balance snapshots never cross the network (every device recomputes from
// the log), so no codec exists for them by design.
