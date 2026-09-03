import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/crypto/identity.dart';
import 'package:vbank/core/crypto/invite_wrap.dart';
import 'package:vbank/core/crypto/sync_envelope.dart';
import 'package:vbank/core/deeplink/deeplink_handler.dart';
import 'package:vbank/models/group.dart';
import 'package:vbank/services/group_key_service.dart';
import 'package:vbank/services/group_service.dart';
import 'package:vbank/services/invite_service.dart';

import 'helpers/test_db.dart';

/// Invite links carry a one-time secret; the snapshot carries the group key
/// wrapped under it for live invites only.
void main() {
  setUp(useInMemoryDatabase);
  tearDown(closeTestDatabase);

  final groupKey = SecretKey(List<int>.generate(32, (i) => 200 - i));

  test('wrap/unwrap round-trips the group key and is bound to group and invite', () async {
    final secret = InviteKeyWrap.randomSecret();
    expect(secret, hasLength(16));
    final wrapped = await InviteKeyWrap.wrap(groupKey: groupKey, secret: secret, groupId: 'g1', inviteId: 'i1');
    final back = await InviteKeyWrap.unwrap(wrapped: wrapped, secret: secret, groupId: 'g1', inviteId: 'i1');
    expect(await back!.extractBytes(), await groupKey.extractBytes());

    expect(await InviteKeyWrap.unwrap(wrapped: wrapped, secret: InviteKeyWrap.randomSecret(), groupId: 'g1', inviteId: 'i1'), isNull,
        reason: 'wrong secret');
    expect(await InviteKeyWrap.unwrap(wrapped: wrapped, secret: secret, groupId: 'g1', inviteId: 'i2'), isNull,
        reason: 'cannot be replayed under another invite');
    expect(await InviteKeyWrap.unwrap(wrapped: wrapped, secret: secret, groupId: 'g2', inviteId: 'i1'), isNull,
        reason: 'nor for another group');

    // The link form survives base64url without padding.
    final encoded = InviteKeyWrap.encodeSecret(secret);
    expect(encoded, isNot(contains('=')));
    expect(InviteKeyWrap.decodeSecret(encoded), secret);
  });

  test('snapshot envelope carries wraps in the clear and decodes them back', () async {
    final secret = InviteKeyWrap.randomSecret();
    final wrapped = await InviteKeyWrap.wrap(groupKey: groupKey, secret: secret, groupId: 'g1', inviteId: 'i1');
    final bytes = await SyncEnvelope.seal(
      type: SyncPayloadType.groupSnapshot,
      groupId: 'g1',
      plaintextJson: {'group': 'hello'},
      groupKey: groupKey,
      wraps: {'i1': wrapped},
    );
    final env = SyncEnvelope.tryDecode(bytes)!;
    expect(env.wraps.keys, ['i1']);
    // A joiner with only the secret: unwrap, then open.
    final key = await InviteKeyWrap.unwrap(wrapped: env.wraps['i1']!, secret: secret, groupId: 'g1', inviteId: 'i1');
    expect((await env.open(key!))['group'], 'hello');
    // Envelopes without wraps (every other record type, old snapshots) still decode.
    final plain = await SyncEnvelope.seal(type: SyncPayloadType.transaction, groupId: 'g1', plaintextJson: {'a': 1}, groupKey: groupKey);
    expect(SyncEnvelope.tryDecode(plain)!.wraps, isEmpty);
  });

  test('createInvite: 12 h expiry, wrapped key stored, secret returned once; liveInvites drops used/expired', () async {
    final admin = await IdentityManager.createIdentity('Admin');
    final invites = InviteService();
    // invites.group_id references groups: create a real (passphrase-less) group.
    final circle = await GroupService(groupKeyService: GroupKeyService(), inviteService: invites).createGroup(
      name: 'Wrap Circle',
      config: const GroupConfig(groupId: '', contributionAmount: 20),
      ownerPeerId: admin.identity.peerId,
      ownerName: 'Admin',
      ownerPublicKey: admin.identity.publicKey,
      ownerKeyPair: admin.keyPair,
    );
    final g1 = circle.id;
    expect(await GroupKeyService().hasKey(g1), isTrue, reason: 'random key generated without a passphrase');
    final created = await invites.createInvite(
      groupId: g1,
      groupCid: 'bafy',
      inviterPeerId: admin.identity.peerId,
      inviterKeyPair: admin.keyPair,
      groupKey: groupKey,
    );
    final inv = created.invite;
    expect(created.secret, isNotNull);
    expect(created.secretB64, isNotNull);
    expect(inv.wrappedKey, isNotNull);
    final ttl = inv.expiresAt.difference(inv.createdAt);
    expect(ttl, const Duration(hours: 12));
    expect((await invites.getById(inv.id))!.wrappedKey, inv.wrappedKey);

    // The stored wrapped key opens with the link secret.
    final key = await InviteKeyWrap.unwrap(
      wrapped: inv.wrappedKey!,
      secret: InviteKeyWrap.decodeSecret(created.secretB64!),
      groupId: g1,
      inviteId: inv.id,
    );
    expect(await key!.extractBytes(), await groupKey.extractBytes());

    expect((await invites.liveInvites(g1)).map((i) => i.id), [inv.id]);
    expect(await invites.liveInvites(g1, now: inv.expiresAt.add(const Duration(seconds: 1))), isEmpty, reason: 'expired');
    await invites.markUsed(inv.id, 'someone');
    expect(await invites.liveInvites(g1), isEmpty, reason: 'used');

    // Snapshot JSON round-trips the wrapped key so other admins republish it.
    final j = InviteService.toSnapshotJson(inv);
    expect(InviteService.fromSnapshotJson(j).wrappedKey, inv.wrappedKey);

    // Legacy: no group key → no secret, no wrapped key.
    final legacy = await invites.createInvite(
      groupId: g1,
      groupCid: 'bafy',
      inviterPeerId: admin.identity.peerId,
      inviterKeyPair: admin.keyPair,
    );
    expect(legacy.secret, isNull);
    expect(legacy.invite.wrappedKey, isNull);
  });

  test('join links carry the secret as k=', () {
    final link = DeepLinkHandler.buildJoinLink(
      groupId: 'g1',
      inviterPeerId: 'me',
      groupCid: 'bafy',
      inviteId: 'i1',
      inviteNonceB64: 'AA==',
      inviteSecretB64: 'c2VjcmV0c2VjcmV0c2Vj',
    );
    expect(link, contains('k=c2VjcmV0c2VjcmV0c2Vj'));
    final r = DeepLinkHandler.parseString(link);
    expect(r.inviteSecretB64, 'c2VjcmV0c2VjcmV0c2Vj');
    expect(DeepLinkHandler.parseString('vbank://join?group=g&inviter=me').inviteSecretB64, isNull);
    expect(Uint8List(0), isEmpty);
  });
}
