import 'dart:convert';

import '../domain/loans.dart';
import '../domain/transactions.dart';

/// Canonical bytes authors sign. Every field is covered so nothing can be
/// altered after the fact; receivers rebuild the exact bytes from the
/// record and verify against the roster's stored key.
///
/// All payload shapes are byte-identical to the legacy app: old and
/// rewritten nodes verify each other's signatures.
abstract final class SigningPayloads {
  /// Millis-truncated UTC instant in ISO form. `DateTime.now()` carries
  /// microseconds but storage keeps milliseconds, so payloads are built on
  /// truncated times: what is signed is what is stored and re-read.
  static DateTime signedInstant(DateTime t) =>
      DateTime.fromMillisecondsSinceEpoch(
        t.toUtc().millisecondsSinceEpoch,
        isUtc: true,
      );

  /// ISO form of [t] for payloads.
  static String signedInstantString(DateTime t) =>
      signedInstant(t).toIso8601String();

  /// Transaction author payload (v2).
  static List<int> transaction(Transaction tx) => utf8.encode(
        jsonEncode({
          'v': 2,
          'id': tx.id,
          'groupId': tx.groupId,
          'author': tx.authorPeerId,
          'from': tx.fromPeerId,
          'to': tx.toPeerId,
          'type': tx.type.name,
          'amount': tx.amount,
          'currency': tx.currency,
          'note': tx.note,
          'timestamp': signedInstantString(tx.timestamp),
          'seq': tx.sequenceNumber,
          'loanId': tx.loanId,
        }),
      );

  /// Loan request payload (v2).
  static List<int> loanRequest(LoanRequest l) => utf8.encode(
        jsonEncode({
          'v': 2,
          'loanId': l.id,
          'groupId': l.groupId,
          'borrower': l.borrowerPeerId,
          'amount': l.requestedAmount,
          'rate': l.interestRate,
          'termWeeks': l.termWeeks,
          'reason': l.reason,
          'requestedAt': signedInstantString(l.requestedAt),
        }),
      );

  /// Loan approval/rejection payload (v2).
  static List<int> loanApproval(LoanRequest l) => utf8.encode(
        jsonEncode({
          'v': 2,
          'loanId': l.id,
          'status': l.status == LoanStatus.rejected ? 'rejected' : 'approved',
          'approvedAmount': l.approvedAmount,
          'approver': l.approvedByPeerId,
          'approvedAt': l.approvedAt == null
              ? null
              : signedInstantString(l.approvedAt!),
        }),
      );

  /// Reversal request payload.
  static List<int> reversalRequest({
    required String reversalId,
    required String groupId,
    required String originalTransactionId,
    required String requestedByPeerId,
    required String reason,
  }) =>
      utf8.encode(
        'vbank:reversal:$reversalId:$groupId:'
        '$originalTransactionId:$requestedByPeerId:$reason',
      );

  /// Reversal decision payload.
  static List<int> reversalDecision({
    required String reversalId,
    required String status,
    required String? approvedByPeerId,
  }) =>
      utf8.encode(
        'vbank:reversal-decision:$reversalId:$status:$approvedByPeerId',
      );

  /// Invite payload over the inviter's nonce and expiry.
  static List<int> invite({
    required String inviteId,
    required String groupId,
    required String inviterPeerId,
    required List<int> nonce,
    required DateTime expiresAt,
  }) =>
      utf8.encode(
        'vbank:invite:$inviteId:$groupId:$inviterPeerId:'
        '${base64UrlEncode(nonce)}:'
        '${expiresAt.toUtc().millisecondsSinceEpoch}',
      );

  /// Member removal payload.
  static List<int> removal({
    required String removalId,
    required String groupId,
    required String removedPeerId,
    required String action,
  }) =>
      utf8.encode(
        'vbank:remove:$removalId:$groupId:$removedPeerId:$action',
      );

  /// Ownership transfer payload (signed by each side in turn).
  static List<int> transfer({
    required String transferId,
    required String groupId,
    required String fromPeerId,
    required String toPeerId,
  }) =>
      utf8.encode('vbank:transfer:$transferId:$groupId:$fromPeerId:$toPeerId');

  /// Group creation payload: binds the first owner to the fresh id.
  static List<int> groupOwner(String groupId, String ownerPeerId) =>
      utf8.encode('$groupId:$ownerPeerId');

  /// Member-key announcement payload over the published X25519 key.
  static List<int> memberKey({
    required String groupId,
    required String peerId,
    required List<int> encKey,
  }) =>
      utf8.encode('vbank:enckey:$groupId:$peerId:${base64Encode(encKey)}');

  /// Join announcement payload over the invite that authorised it.
  static List<int> memberJoin({
    required String groupId,
    required String peerId,
    required String inviteId,
  }) =>
      utf8.encode('vbank:join:$groupId:$peerId:$inviteId');
}
