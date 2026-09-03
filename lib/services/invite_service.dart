import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto/invite_wrap.dart';
import '../core/crypto/signing.dart';
import '../core/storage/invite_dao.dart';

class InviteException implements Exception {
  final String message;
  const InviteException(this.message);
  @override
  String toString() => message;
}

/// Invites (DESIGN_PLAN §16): each has a unique nonce, an expiry and the
/// inviter's signature. One-use is enforced by every admin device marking the
/// invite used when the join is accepted and republishing the group snapshot.
class InviteService {
  final InviteDao _dao;
  static const _uuid = Uuid();
  /// Invites are short-lived by design: the link is the secret.
  static const defaultExpiry = Duration(hours: 12);

  InviteService({InviteDao? dao}) : _dao = dao ?? InviteDao();

  static List<int> signingPayload({
    required String inviteId,
    required String groupId,
    required String inviterPeerId,
    required List<int> nonce,
    required DateTime expiresAt,
  }) =>
      utf8.encode(
        'vbank:invite:$inviteId:$groupId:$inviterPeerId:${base64UrlEncode(nonce)}:${expiresAt.toUtc().millisecondsSinceEpoch}',
      );

  static Uint8List _randomNonce() {
    final rng = Random.secure();
    return Uint8List.fromList(List<int>.generate(16, (_) => rng.nextInt(256)));
  }

  /// Creates and stores a signed invite. The caller has already checked the
  /// inviter is an owner/admin.
  ///
  /// With [groupKey] the invite also gets the group key wrapped under a fresh
  /// one-time secret (InviteKeyWrap); the secret is returned once, for the
  /// link, and never stored. Without it (legacy) the joiner needs the group
  /// passphrase.
  Future<CreatedInvite> createInvite({
    required String groupId,
    required String groupCid,
    required String inviterPeerId,
    required SimpleKeyPair inviterKeyPair,
    SecretKey? groupKey,
    Duration expiry = defaultExpiry,
  }) async {
    final id = _uuid.v4();
    final nonce = _randomNonce();
    final now = DateTime.now().toUtc();
    final expiresAt = now.add(expiry);
    final secret = groupKey == null ? null : InviteKeyWrap.randomSecret();
    final wrappedKey = groupKey == null
        ? null
        : await InviteKeyWrap.wrap(groupKey: groupKey, secret: secret!, groupId: groupId, inviteId: id);

    final signature = await SigningService.sign(
      signingPayload(
        inviteId: id,
        groupId: groupId,
        inviterPeerId: inviterPeerId,
        nonce: nonce,
        expiresAt: expiresAt,
      ),
      inviterKeyPair,
    );

    final invite = InviteData(
      id: id,
      groupId: groupId,
      cid: groupCid,
      createdAt: now,
      expiresAt: expiresAt,
      nonce: nonce,
      inviterPeerId: inviterPeerId,
      inviterSignature: Uint8List.fromList(signature.bytes),
      wrappedKey: wrappedKey,
    );
    await _dao.upsert(invite);
    return CreatedInvite(invite, secret);
  }

  /// Invites that can still be used: not used, not expired. Only these get a
  /// wrapped-key entry in the snapshot header.
  Future<List<InviteData>> liveInvites(String groupId, {DateTime? now}) async {
    final at = now ?? DateTime.now().toUtc();
    return (await _dao.getByGroupId(groupId)).where((i) => !i.used && at.isBefore(i.expiresAt)).toList();
  }

  /// Validates an invite against the roster's copy of the inviter's key.
  /// Throws [InviteException] with a user-facing reason on failure.
  static Future<void> verify(
    InviteData invite, {
    required String groupId,
    required List<int> presentedNonce,
    required List<int> inviterPublicKey,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now().toUtc();
    if (invite.groupId != groupId) throw const InviteException('Invite is for a different group');
    if (invite.used) throw const InviteException('This invite has already been used');
    if (at.isAfter(invite.expiresAt)) throw const InviteException('This invite has expired');
    final nonce = invite.nonce;
    final inviter = invite.inviterPeerId;
    final sig = invite.inviterSignature;
    if (nonce == null || inviter == null || sig == null) {
      throw const InviteException('Invite is incomplete');
    }
    if (!_constantTimeEquals(nonce, presentedNonce)) {
      throw const InviteException('Invite code does not match');
    }
    final ok = await SigningService.verifyWithBytes(
      signingPayload(
        inviteId: invite.id,
        groupId: invite.groupId,
        inviterPeerId: inviter,
        nonce: nonce,
        expiresAt: invite.expiresAt,
      ),
      sig,
      inviterPublicKey,
    );
    if (!ok) throw const InviteException('Invite signature is invalid');
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<InviteData?> getById(String id) => _dao.getById(id);
  Future<List<InviteData>> getByGroupId(String groupId) => _dao.getByGroupId(groupId);
  Future<void> markUsed(String id, String usedByPeerId) => _dao.markUsed(id, usedByPeerId);
  Future<void> upsert(InviteData invite) => _dao.upsert(invite);
  Future<void> delete(String id) => _dao.delete(id);
  Future<void> purgeExpired(String groupId) => _dao.deleteExpired(groupId, DateTime.now().toUtc());

  // --- snapshot (de)serialisation -------------------------------------------

  static Map<String, dynamic> toSnapshotJson(InviteData i) => {
    'id': i.id,
    'groupId': i.groupId,
    'cid': i.cid,
    'used': i.used,
    'usedBy': i.usedByPeerId,
    'createdAt': i.createdAt.toIso8601String(),
    'expiresAt': i.expiresAt.toIso8601String(),
    'nonce': i.nonce == null ? null : base64Encode(i.nonce!),
    'inviter': i.inviterPeerId,
    'signature': i.inviterSignature == null ? null : base64Encode(i.inviterSignature!),
    'wrappedKey': i.wrappedKey == null ? null : base64Encode(i.wrappedKey!),
  };

  static InviteData fromSnapshotJson(Map<String, dynamic> j) => InviteData(
    id: j['id'] as String,
    groupId: j['groupId'] as String,
    cid: j['cid'] as String?,
    used: j['used'] as bool? ?? false,
    usedByPeerId: j['usedBy'] as String?,
    createdAt: DateTime.parse(j['createdAt'] as String).toUtc(),
    expiresAt: DateTime.parse(j['expiresAt'] as String).toUtc(),
    nonce: j['nonce'] != null ? Uint8List.fromList(base64Decode(j['nonce'] as String)) : null,
    inviterPeerId: j['inviter'] as String?,
    inviterSignature: j['signature'] != null
        ? Uint8List.fromList(base64Decode(j['signature'] as String))
        : null,
    wrappedKey: j['wrappedKey'] != null ? Uint8List.fromList(base64Decode(j['wrappedKey'] as String)) : null,
  );

  /// Merges invites from a peer's snapshot: a `used` flag never reverts.
  Future<void> mergeFromSnapshot(List<InviteData> incoming) async {
    for (final inc in incoming) {
      final local = await _dao.getById(inc.id);
      if (local == null) {
        await _dao.upsert(inc);
      } else if (inc.used && !local.used) {
        await _dao.markUsed(inc.id, inc.usedByPeerId ?? '');
      }
    }
  }
}

/// A freshly created invite and, when the group key was wrapped, the one-time
/// secret that goes into the link (`k=`).
class CreatedInvite {
  final InviteData invite;
  final Uint8List? secret;
  const CreatedInvite(this.invite, this.secret);
  String? get secretB64 => secret == null ? null : InviteKeyWrap.encodeSecret(secret!);
}
