import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/invite_wrap.dart';
import '../crypto/signing.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/invites.dart';
import '../domain/repositories.dart';
import 'context.dart';
import 'signing_payloads.dart';

/// One-use tickets into groups.
///
/// An invite carries the group key *wrapped* under a fresh one-time secret;
/// the secret rides the link and is never stored. Consuming marks the
/// invite used, and a used flag never reverts — every admin device
/// converges on it through snapshots.
final class InviteService {
  /// Invite storage.
  final InviteRepository invites;

  /// Device signer.
  final SignPayload sign;

  /// Clock for creation and expiry.
  final AppClock clock;

  /// Record ids.
  final IdGenerator ids;

  /// Invite lifetime: short by design, since the link is the secret.
  static const Duration defaultExpiry = Duration(hours: 12);

  /// Creates an invite service.
  InviteService({
    required this.invites,
    required this.sign,
    required this.clock,
    required this.ids,
  });

  /// Creates and stores a signed invite. The caller checked the inviter is
  /// an owner/admin. With [groupKey] the invite wraps it under a fresh
  /// secret (returned once, for the link, never stored); without it the
  /// joiner falls back to the group passphrase.
  Future<Result<CreatedInvite>> createInvite({
    required String groupId,
    required String groupCid,
    required String groupTopic,
    required String inviterPeerId,
    required String inviterName,
    required SecretKey groupKey,
    Duration expiry = defaultExpiry,
  }) async {
    final String id = ids();
    final Uint8List nonce = InviteKeyWrap.randomSecret();
    final DateTime now = clock().toUtc();
    final DateTime expiresAt = now.add(expiry);
    final Uint8List secret = InviteKeyWrap.randomSecret();
    final Uint8List wrapped = await InviteKeyWrap.wrap(
      groupKey: groupKey,
      secret: secret,
      groupId: groupId,
      inviteId: id,
    );
    final Invite unsigned = Invite(
      id: id,
      groupId: groupId,
      groupCid: groupCid,
      groupTopic: groupTopic,
      inviterPeerId: inviterPeerId,
      inviterName: inviterName,
      wrappedKey: wrapped,
      createdAt: now,
      expiresAt: expiresAt,
      nonce: nonce,
      inviterSignature: Uint8List(0),
    );
    final Invite signed = unsigned.copyWith(
      inviterSignature: await sign(
        SigningPayloads.invite(
          inviteId: id,
          groupId: groupId,
          inviterPeerId: inviterPeerId,
          nonce: nonce,
          expiresAt: expiresAt,
        ),
      ),
    );
    final Result<Unit> saved = await invites.save(signed);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(CreatedInvite(signed, secret));
  }

  /// Invites that can still be used: not consumed, not expired at [now].
  /// Only these earn a wrapped-key entry in snapshots.
  Future<Result<List<Invite>>> liveInvites(
    String groupId, {
    DateTime? now,
  }) async {
    final Result<List<Invite>> all = await invites.listByGroup(groupId);
    if (all.isErr) {
      return all;
    }
    final DateTime at = (now ?? clock()).toUtc();
    return Ok([
      for (final Invite i in all.value)
        if (i.isValidAt(at)) i,
    ]);
  }

  /// Validates an invite against the roster's copy of the inviter's key.
  /// Failure reasons are stable codes for presentation.
  static Future<Result<Unit>> verify(
    Invite invite, {
    required String groupId,
    required List<int> presentedNonce,
    required List<int> inviterPublicKey,
    required DateTime now,
  }) async {
    if (invite.groupId != groupId) {
      return const Err(ValidationFailure('inviteWrongGroup'));
    }
    if (invite.used) {
      return const Err(ConflictFailure('inviteUsed'));
    }
    if (invite.isExpiredAt(now.toUtc())) {
      return const Err(ConflictFailure('inviteExpired'));
    }
    if (!_constantTimeEquals(invite.nonce, presentedNonce)) {
      return const Err(ValidationFailure('inviteNonceMismatch'));
    }
    final bool ok = await SigningService.verifyWithBytes(
      SigningPayloads.invite(
        inviteId: invite.id,
        groupId: invite.groupId,
        inviterPeerId: invite.inviterPeerId,
        nonce: invite.nonce,
        expiresAt: invite.expiresAt,
      ),
      invite.inviterSignature,
      inviterPublicKey,
    );
    if (!ok) {
      return const Err(IntegrityFailure('invite:signature'));
    }
    return const Ok(unit);
  }

  /// Merges invites from a peer's snapshot: a `used` flag never reverts.
  Future<Result<Unit>> mergeUsed(List<Invite> incoming) async {
    for (final Invite inc in incoming) {
      final Result<Invite> local = await invites.findById(inc.id);
      if (local.isErr) {
        final Result<Unit> saved = await invites.save(inc);
        if (saved.isErr) {
          return saved;
        }
      } else if (inc.used && !local.value.used) {
        final Result<Unit> marked = await invites.markUsed(inc.id);
        if (marked.isErr) {
          return marked;
        }
      }
    }
    return const Ok(unit);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  /// One invite, or `Err(NotFoundFailure)`.
  Future<Result<Invite>> getById(String id) => invites.findById(id);
}

/// A freshly created invite and, when the group key was wrapped, the
/// one-time secret that goes into the link. The secret is returned once
/// and never stored.
final class CreatedInvite {
  /// The stored invite (with the wrapped key, without the secret).
  final Invite invite;

  /// The link secret, or null for passphrase-only invites.
  final Uint8List? secret;

  /// Creates the creation result.
  const CreatedInvite(this.invite, this.secret);

  /// Link form of the secret, or null when passphrase-only.
  String? get secretLink =>
      secret == null ? null : InviteKeyWrap.encodeSecret(secret!);
}
