import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/invites.dart';
import 'dto.dart';

/// Row mapping for `invites`.
abstract final class InviteDto {
  /// Serializes [invite] to an `invites` row.
  static Map<String, Object?> toRow(Invite invite) => {
        'id': invite.id,
        'group_id': invite.groupId,
        'group_cid': invite.groupCid,
        'group_topic': invite.groupTopic,
        'inviter_peer_id': invite.inviterPeerId,
        'inviter_name': invite.inviterName,
        'wrapped_key': invite.wrappedKey,
        'created_at': Dto.instantValue(invite.createdAt),
        'expires_at': Dto.instantValue(invite.expiresAt),
        'used': Dto.flagValue(invite.used),
        'used_by_peer_id': invite.usedByPeerId,
        'nonce': invite.nonce,
        'inviter_signature': invite.inviterSignature,
      };

  /// Parses an `invites` row.
  static Result<Invite> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        Invite(
          id: Dto.text(row, 'id'),
          groupId: Dto.text(row, 'group_id'),
          groupCid: Dto.text(row, 'group_cid'),
          groupTopic: Dto.text(row, 'group_topic'),
          inviterPeerId: Dto.text(row, 'inviter_peer_id'),
          inviterName: Dto.text(row, 'inviter_name'),
          wrappedKey: Dto.bytesOrNull(row, 'wrapped_key'),
          createdAt: Dto.instant(row, 'created_at'),
          expiresAt: Dto.instant(row, 'expires_at'),
          used: Dto.flag(row, 'used'),
          usedByPeerId: Dto.textOrNull(row, 'used_by_peer_id'),
          nonce: Dto.bytes(row, 'nonce'),
          inviterSignature: Dto.bytes(row, 'inviter_signature'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
