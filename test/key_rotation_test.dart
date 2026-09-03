import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/crypto/identity.dart';
import 'package:vbank/core/crypto/member_keys.dart';
import 'package:vbank/core/crypto/signing.dart';
import 'package:vbank/core/crypto/sync_envelope.dart';
import 'package:vbank/models/group.dart';
import 'package:vbank/services/group_key_service.dart';
import 'package:vbank/services/group_service.dart';
import 'package:vbank/services/transaction_service.dart';
import 'package:vbank/services/invite_service.dart';

import 'helpers/test_db.dart';

/// Key rotation on member removal, re-keying members, and the re-join block.
void main() {
  setUp(useInMemoryDatabase);
  tearDown(closeTestDatabase);

  test('member X25519 keys are deterministic from the identity seed; sealing is bound to the recipient', () async {
    final alice = await IdentityManager.createIdentity('Alice');
    final bob = await IdentityManager.createIdentity('Bob');
    final a1 = await MemberKeys.fromIdentitySeed(await SigningService.extractSeed(alice.keyPair));
    final a2 = await MemberKeys.fromIdentitySeed(await SigningService.extractSeed(alice.keyPair));
    expect(await MemberKeys.publicKeyBytes(a1), await MemberKeys.publicKeyBytes(a2), reason: 'same seed, same key');
    final b = await MemberKeys.fromIdentitySeed(await SigningService.extractSeed(bob.keyPair));

    final ring = GroupKeyRing({1: Uint8List.fromList(List.filled(32, 1)), 2: Uint8List.fromList(List.filled(32, 2))});
    final sealed = await MemberKeys.seal(
      plaintext: ring.encode(),
      sender: a1,
      recipientPublicKey: await MemberKeys.publicKeyBytes(b),
      groupId: 'g1',
      recipientPeerId: bob.identity.peerId,
    );
    final opened = await MemberKeys.open(sealed: sealed, recipient: b, groupId: 'g1', recipientPeerId: bob.identity.peerId);
    expect(GroupKeyRing.decode(opened!)!.keys, ring.keys);
    expect(await MemberKeys.open(sealed: sealed, recipient: a1, groupId: 'g1', recipientPeerId: bob.identity.peerId), isNull,
        reason: 'only Bob can open it');
    expect(await MemberKeys.open(sealed: sealed, recipient: b, groupId: 'g1', recipientPeerId: 'someone-else'), isNull,
        reason: 'bound to the recipient peer id');
    // A bare key decodes as version 1.
    expect(GroupKeyRing.decode(List.filled(32, 9))!.currentVersion, 1);
  });

  test('rotation: new records need the new version; old keys read nothing new', () async {
    final owner = await IdentityManager.createIdentity('Owner');
    final keys = GroupKeyService();
    final groups = GroupService(groupKeyService: keys, inviteService: InviteService());
    final circle = await groups.createGroup(
      name: 'Rotation Circle',
      config: const GroupConfig(groupId: '', contributionAmount: 20),
      ownerPeerId: owner.identity.peerId,
      ownerName: 'Owner',
      ownerPublicKey: owner.identity.publicKey,
      ownerKeyPair: owner.keyPair,
    );
    final g = circle.id;
    expect(await keys.currentVersion(g), 1);
    final v1 = (await keys.ring(g))!.current;

    final ring = await keys.rotate(g);
    expect(ring.currentVersion, 2);
    expect(ring[1], v1, reason: 'history kept for reading old records');
    expect(await keys.currentVersion(g), 2);
    expect(await (await keys.keyFor(g, 1))!.extractBytes(), v1);
    expect(await (await keys.keyFor(g, 2))!.extractBytes(), ring[2]);
    expect(await keys.keyFor(g, 3), isNull);

    // A record sealed with version 2 cannot be opened with version 1 (the
    // removed member's key), and the version is bound into the AAD.
    final sealed = await SyncEnvelope.seal(
      type: SyncPayloadType.transaction,
      groupId: g,
      plaintextJson: {'amount': 20},
      groupKey: SecretKey(ring.current),
      keyVersion: 2,
    );
    final env = SyncEnvelope.tryDecode(sealed)!;
    expect(env.keyVersion, 2);
    expect((await env.open(SecretKey(ring.current)))['amount'], 20);
    expect(() => env.open(SecretKey(v1)), throwsA(isA<EnvelopeAuthException>()));

    // A member device importing the sealed ring moves to the new version.
    // (Same in-memory DB here, so the "other device" uses its own group row.)
    const g2 = 'other-device-copy';
    final other = GroupKeyService();
    await other.setKey(g2, SecretKey(v1));
    expect(await other.currentVersion(g2), 1);
    await other.importRing(g2, ring);
    expect(await other.currentVersion(g2), 2);
    expect(await (await other.keyFor(g2, 2))!.extractBytes(), ring[2]);
    // Importing an older ring never moves backwards.
    await other.importRing(g2, GroupKeyRing({1: v1}));
    expect(await other.currentVersion(g2), 2);
  });

  test('a removed member is banned from re-joining until the owner allows them back', () async {
    final owner = await IdentityManager.createIdentity('Owner');
    final gone = await IdentityManager.createIdentity('Gone');
    final groups = GroupService(groupKeyService: GroupKeyService(), inviteService: InviteService());
    final circle = await groups.createGroup(
      name: 'Ban Circle',
      config: const GroupConfig(groupId: '', contributionAmount: 20),
      ownerPeerId: owner.identity.peerId,
      ownerName: 'Owner',
      ownerPublicKey: owner.identity.publicKey,
      ownerKeyPair: owner.keyPair,
    );
    await groups.addMember(
      groupId: circle.id,
      member: Member(peerId: gone.identity.peerId, name: 'Gone', joinedAt: DateTime.utc(2026), publicKey: gone.identity.publicKey),
    );
    expect(await groups.isBanned(circle.id, gone.identity.peerId), isFalse);
    await groups.removeMember(
      groupId: circle.id,
      actingPeerId: owner.identity.peerId,
      actingKeyPair: owner.keyPair,
      peerId: gone.identity.peerId,
      reason: 'left town',
    );
    expect(await groups.isBanned(circle.id, gone.identity.peerId), isTrue);
    expect((await groups.bannedMembers(circle.id)).map((r) => r.removedPeerId), [gone.identity.peerId]);

    // Pending re-join cannot be approved while banned.
    await groups.addMember(
      groupId: circle.id,
      member: Member(
        peerId: gone.identity.peerId, name: 'Gone', joinedAt: DateTime.utc(2026, 2),
        publicKey: gone.identity.publicKey, status: MemberStatus.pending,
      ),
    );
    expect(
      () => groups.approveMember(groupId: circle.id, actingPeerId: owner.identity.peerId, peerId: gone.identity.peerId),
      throwsA(isA<PermissionException>()),
    );

    // Only the owner can lift it; then approval works and the ban is gone.
    await groups.liftRemoval(groupId: circle.id, actingPeerId: owner.identity.peerId, peerId: gone.identity.peerId);
    expect(await groups.isBanned(circle.id, gone.identity.peerId), isFalse);
    expect(await groups.bannedMembers(circle.id), isEmpty);
    await groups.approveMember(groupId: circle.id, actingPeerId: owner.identity.peerId, peerId: gone.identity.peerId);
    // Snapshot JSON keeps the lift.
    final r = (await groups.removals(circle.id)).first;
    expect(r.lifted, isTrue);
    expect(r.toJson()['lifted'], isTrue);
  });
}
