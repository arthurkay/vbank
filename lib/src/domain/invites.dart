import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';

/// A one-use ticket into a group, shared as a QR code or link.
///
/// Unlike the old model, expiry is a pure function of an explicit clock:
/// pass `now` in so tests pin time instead of racing it.
final class Invite {
  /// This invite's id.
  final String id;

  /// The group it opens.
  final String groupId;

  /// CID of the group's encrypted metadata for fetching.
  final String groupCid;

  /// PubSub topic to announce on after joining.
  final String groupTopic;

  /// Who sent it.
  final String inviterPeerId;

  /// Who sent it, in human words.
  final String inviterName;

  /// The group key wrapped under this invite's one-time secret (null for
  /// passphrase-only invites). The secret itself rides the link and is
  /// never stored.
  final Uint8List? wrappedKey;

  /// When it was created.
  final DateTime createdAt;

  /// When it stops working (12 hours after creation by default).
  final DateTime expiresAt;

  /// True once consumed. Never reverts — like a used ticket.
  final bool used;

  /// Who consumed it, once consumed.
  final String? usedByPeerId;

  /// Unique per invite; the group records it so replays are rejected.
  final Uint8List nonce;

  /// The inviter's signature over the payload.
  final Uint8List inviterSignature;

  /// Creates an invite.
  const Invite({
    required this.id,
    required this.groupId,
    required this.groupCid,
    required this.groupTopic,
    required this.inviterPeerId,
    required this.inviterName,
    this.wrappedKey,
    required this.createdAt,
    required this.expiresAt,
    this.used = false,
    this.usedByPeerId,
    required this.nonce,
    required this.inviterSignature,
  });

  /// True when [now] is past [expiresAt].
  bool isExpiredAt(DateTime now) => now.isAfter(expiresAt);

  /// True when unconsumed and unexpired at [now].
  bool isValidAt(DateTime now) => !used && !isExpiredAt(now);

  /// Structural checks: identifiers present, expiry after creation.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('inviteIdEmpty'));
    }
    if (groupId.isEmpty) {
      return const Err(ValidationFailure('inviteGroupEmpty'));
    }
    if (!expiresAt.isAfter(createdAt)) {
      return const Err(ValidationFailure('inviteExpiryNotAfterCreation'));
    }
    return const Ok(unit);
  }

  /// Copies this invite, replacing the given fields.
  Invite copyWith({
    bool? used,
    String? usedByPeerId,
    Uint8List? wrappedKey,
    Uint8List? inviterSignature,
  }) =>
      Invite(
        id: id,
        groupId: groupId,
        groupCid: groupCid,
        groupTopic: groupTopic,
        inviterPeerId: inviterPeerId,
        inviterName: inviterName,
        wrappedKey: wrappedKey ?? this.wrappedKey,
        createdAt: createdAt,
        expiresAt: expiresAt,
        used: used ?? this.used,
        usedByPeerId: usedByPeerId ?? this.usedByPeerId,
        nonce: nonce,
        inviterSignature: inviterSignature ?? this.inviterSignature,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Invite &&
          id == other.id &&
          groupId == other.groupId &&
          groupCid == other.groupCid &&
          groupTopic == other.groupTopic &&
          inviterPeerId == other.inviterPeerId &&
          inviterName == other.inviterName &&
          (wrappedKey == null || other.wrappedKey == null
              ? wrappedKey == other.wrappedKey
              : bytesEqual(wrappedKey!, other.wrappedKey!)) &&
          createdAt == other.createdAt &&
          expiresAt == other.expiresAt &&
          used == other.used &&
          usedByPeerId == other.usedByPeerId &&
          bytesEqual(nonce, other.nonce) &&
          bytesEqual(inviterSignature, other.inviterSignature);

  @override
  int get hashCode => Object.hash(
        id,
        groupId,
        groupCid,
        groupTopic,
        inviterPeerId,
        inviterName,
        wrappedKey == null ? null : bytesHash(wrappedKey!),
        createdAt,
        expiresAt,
        used,
        usedByPeerId,
        bytesHash(nonce),
        bytesHash(inviterSignature),
      );
}
