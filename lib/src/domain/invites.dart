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

  /// The group symmetric key, wrapped for the recipient.
  final Uint8List groupKey;

  /// When it was created.
  final DateTime createdAt;

  /// When it stops working (default: 7 days after creation).
  final DateTime expiresAt;

  /// True once consumed. Never reverts — like a used ticket.
  final bool used;

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
    required this.groupKey,
    required this.createdAt,
    required this.expiresAt,
    this.used = false,
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
  Invite copyWith({bool? used}) => Invite(
        id: id,
        groupId: groupId,
        groupCid: groupCid,
        groupTopic: groupTopic,
        inviterPeerId: inviterPeerId,
        inviterName: inviterName,
        groupKey: groupKey,
        createdAt: createdAt,
        expiresAt: expiresAt,
        used: used ?? this.used,
        nonce: nonce,
        inviterSignature: inviterSignature,
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
          bytesEqual(groupKey, other.groupKey) &&
          createdAt == other.createdAt &&
          expiresAt == other.expiresAt &&
          used == other.used &&
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
        bytesHash(groupKey),
        createdAt,
        expiresAt,
        used,
        bytesHash(nonce),
        bytesHash(inviterSignature),
      );
}
