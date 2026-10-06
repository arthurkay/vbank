import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/crypto/encryption.dart';
import 'package:vbank/src/crypto/invite_wrap.dart';
import 'package:vbank/src/crypto/key_derivation.dart';
import 'package:vbank/src/crypto/member_keys.dart';
import 'package:vbank/src/crypto/signing.dart';
import 'package:vbank/src/crypto/sync_envelope.dart';
import 'package:vbank/src/crypto/wire_codec.dart';

void main() {
  group('WireCodec', () {
    test('round-trips maps, lists and bytes', () {
      final Map<String, Object?> value = {
        's': 'hi',
        'n': 42,
        'b': true,
        'nil': null,
        'list': [1, 'two'],
        'bytes': Uint8List.fromList([1, 2, 3]),
      };
      final Object? back = WireCodec.tryDecode(WireCodec.encode(value));

      expect(back, value);
    });

    test('rejects garbage and non-maps', () {
      expect(WireCodec.tryDecode([]), isNull);
      expect(WireCodec.tryDecode([1, 2, 3]), isNull);
      expect(WireCodec.tryDecode(utf8.encode('{nope')), isNull);
      expect(WireCodec.tryDecodeMap(WireCodec.encode([1])), isNull);
    });

    test('reads legacy JSON payloads', () {
      expect(
        WireCodec.tryDecode(utf8.encode('{"a":1}')),
        {'a': 1},
      );
    });
  });

  group('EncryptedData', () {
    test('compares by value', () async {
      final SecretKey key = SecretKey(List.filled(32, 1));
      final EncryptedData a = await EncryptionService.encrypt(
        utf8.encode('x'),
        key,
      );
      final EncryptedData b = EncryptedData(
        ciphertext: [...a.ciphertext],
        nonce: [...a.nonce],
        mac: [...a.mac],
      );

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a ==
            EncryptedData(
              ciphertext: [...a.ciphertext, 0],
              nonce: [...a.nonce],
              mac: [...a.mac],
            ),
        isFalse,
      );
    });
  });

  group('EncryptionService', () {
    test('round-trips with associated data', () async {
      final SecretKey key = SecretKey(List.filled(32, 1));
      final EncryptedData enc = await EncryptionService.encrypt(
        utf8.encode('village books'),
        key,
        aad: utf8.encode('g-1'),
      );

      expect(
        await EncryptionService.decrypt(enc, key, aad: utf8.encode('g-1')),
        utf8.encode('village books'),
      );
    });

    test('rejects wrong keys, swapped headers and tampering', () async {
      final SecretKey key = SecretKey(List.filled(32, 1));
      final SecretKey other = SecretKey(List.filled(32, 2));
      final EncryptedData enc = await EncryptionService.encrypt(
        utf8.encode('x'),
        key,
        aad: utf8.encode('g-1'),
      );

      await expectLater(
        EncryptionService.decrypt(enc, other, aad: utf8.encode('g-1')),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      await expectLater(
        EncryptionService.decrypt(enc, key, aad: utf8.encode('g-2')),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
      final EncryptedData tampered = EncryptedData(
        ciphertext: [enc.ciphertext.first ^ 0xff, ...enc.ciphertext.skip(1)],
        nonce: enc.nonce,
        mac: enc.mac,
      );
      await expectLater(
        EncryptionService.decrypt(tampered, key, aad: utf8.encode('g-1')),
        throwsA(isA<SecretBoxAuthenticationError>()),
      );
    });
  });

  group('SigningService', () {
    test('signs, verifies and rejects forgeries', () async {
      final SimpleKeyPair pair = await SigningService.generateKeyPair();
      final SimplePublicKey pub = await pair.extractPublicKey();
      final List<int> data = utf8.encode('pay alice 100');
      final Signature sig = await SigningService.sign(data, pair);

      expect(await SigningService.verify(data, sig.bytes, pub), isTrue);
      expect(
        await SigningService.verifyWithBytes(data, sig.bytes, pub.bytes),
        isTrue,
      );
      expect(
        await SigningService.verify(
          utf8.encode('pay alice 101'),
          sig.bytes,
          pub,
        ),
        isFalse,
      );
      final SimpleKeyPair other = await SigningService.generateKeyPair();
      final SimplePublicKey otherPub = await other.extractPublicKey();
      expect(
        await SigningService.verify(data, sig.bytes, otherPub),
        isFalse,
      );
    });

    test('key pairs survive a seed round-trip', () async {
      final SimpleKeyPair pair = await SigningService.generateKeyPair();
      final List<int> seed = await SigningService.extractSeed(pair);
      final SimpleKeyPair rebuilt = await SigningService.keyPairFromSeed(seed);

      expect(
        await SigningService.extractPublicKeyBytes(rebuilt),
        await SigningService.extractPublicKeyBytes(pair),
      );
    });
  });

  group('KeyDerivation', () {
    test('group keys are stable per group and differ across groups', () async {
      Future<List<int>> bytes(String passphrase, String group) async {
        final SecretKey key =
            await KeyDerivation.deriveGroupKeyFromPassphrase(
          passphrase,
          group,
          iterations: 1000,
        );
        return key.extractBytes();
      }

      expect(
        await bytes(' harvest moon ', 'g-1'),
        await bytes('harvest moon', 'g-1'),
        reason: 'passphrases trim',
      );
      expect(
        await bytes('harvest moon', 'g-1'),
        isNot(await bytes('harvest moon', 'g-2')),
      );
    });

    test('passphrase and high-entropy paths differ in kind', () async {
      final SecretKey a = await KeyDerivation.deriveFromPassphrase(
        '1234',
        List.filled(16, 9),
        iterations: 1000,
      );
      final SecretKey b = await KeyDerivation.deriveFromPassphrase(
        '1234',
        List.filled(16, 9),
        iterations: 1000,
      );
      expect(await a.extractBytes(), await b.extractBytes());

      final SecretKey dbKey = await KeyDerivation.deriveLocalDbKey(
        await KeyDerivation.deriveGroupKey('secret'),
        List.filled(32, 3),
      );
      expect((await dbKey.extractBytes()).length, 32);
      expect(KeyDerivation.randomBytes(), hasLength(16));
    });
  });

  group('SyncEnvelope', () {
    test('seals and opens with wraps and rekeys intact', () async {
      final SecretKey key = SecretKey(List.filled(32, 5));
      final Uint8List sealed = await SyncEnvelope.seal(
        type: SyncPayloadType.transaction,
        groupId: 'g-1',
        plaintextJson: {'id': 't-1', 'amount': 100},
        groupKey: key,
        wraps: {'invite-1': Uint8List.fromList([1, 2])},
        keyVersion: 2,
        rekeys: {'alice': Uint8List.fromList([3])},
      );

      final SyncEnvelope? envelope = SyncEnvelope.tryDecode(sealed);
      expect(envelope, isNotNull);
      expect(envelope!.version, SyncEnvelope.currentVersion);
      expect(envelope.type, SyncPayloadType.transaction);
      expect(envelope.keyVersion, 2);
      expect(envelope.wraps.keys, ['invite-1']);
      expect(envelope.rekeys.keys, ['alice']);
      expect(await envelope.open(key), {'id': 't-1', 'amount': 100});
    });

    test('rejects wrong keys, swapped groups and bit flips', () async {
      final SecretKey key = SecretKey(List.filled(32, 5));
      final Uint8List sealed = await SyncEnvelope.seal(
        type: SyncPayloadType.loan,
        groupId: 'g-1',
        plaintextJson: {'id': 'l-1'},
        groupKey: key,
      );
      final SyncEnvelope envelope = SyncEnvelope.tryDecode(sealed)!;

      await expectLater(
        envelope.open(SecretKey(List.filled(32, 6))),
        throwsA(isA<EnvelopeAuthException>()),
      );

      // A swapped group id breaks the AAD binding.
      final Uint8List reswapped = await SyncEnvelope.seal(
        type: SyncPayloadType.loan,
        groupId: 'g-2',
        plaintextJson: {'id': 'l-1'},
        groupKey: key,
      );
      final SyncEnvelope swapped = SyncEnvelope.tryDecode(reswapped)!;
      final SyncEnvelope tampered = SyncEnvelope(
        type: swapped.type,
        groupId: 'g-1',
        data: swapped.data,
      );
      await expectLater(
        tampered.open(key),
        throwsA(isA<EnvelopeAuthException>()),
      );

      final Uint8List flipped = Uint8List.fromList(sealed)..[50] ^= 0xff;
      final SyncEnvelope? broken = SyncEnvelope.tryDecode(flipped);
      if (broken != null) {
        await expectLater(
          broken.open(key),
          throwsA(isA<EnvelopeAuthException>()),
        );
      }
    });

    test('reads v1 JSON envelopes', () async {
      // v1 carried the same fields as base64 JSON. The version binds into
      // the AAD, so a v1 envelope only opens with its v1-sealed bytes;
      // here the decode path (base64 fields, version default) is proven —
      // decryption itself is proven by the v2 round-trips above.
      final SecretKey key = SecretKey(List.filled(32, 5));
      final Uint8List sealed = await SyncEnvelope.seal(
        type: SyncPayloadType.meeting,
        groupId: 'g-1',
        plaintextJson: {'id': 'm-1'},
        groupKey: key,
      );
      final SyncEnvelope v2 = SyncEnvelope.tryDecode(sealed)!;
      String b64(List<int> v) => base64Encode(v);
      final String v1 = jsonEncode({
        'v': 1,
        'type': 'meeting',
        'groupId': 'g-1',
        'nonce': b64(v2.data.nonce),
        'mac': b64(v2.data.mac),
        'ciphertext': b64(v2.data.ciphertext),
      });

      final SyncEnvelope? envelope = SyncEnvelope.tryDecode(
        utf8.encode(v1),
      );
      expect(envelope, isNotNull);
      expect(envelope!.version, 1);
      expect(envelope.type, SyncPayloadType.meeting);
      expect(envelope.groupId, 'g-1');
      expect(envelope.data.nonce, v2.data.nonce);
      expect(envelope.data.ciphertext, v2.data.ciphertext);
    });

    test('auth failures name themselves', () {
      expect(
        const EnvelopeAuthException('tampered').toString(),
        'tampered',
      );
    });

    test('tryDecode rejects garbage and unknown types', () {
      expect(SyncEnvelope.tryDecode([]), isNull);
      expect(SyncEnvelope.tryDecode(utf8.encode('nope')), isNull);
      expect(
        SyncEnvelope.tryDecode(
          WireCodec.encode({'type': 'teleport', 'groupId': 'g'}),
        ),
        isNull,
      );
    });
  });

  group('InviteKeyWrap', () {
    test('wraps and unwraps, rejects strangers', () async {
      final SecretKey key = SecretKey(List.filled(32, 9));
      final Uint8List secret = InviteKeyWrap.randomSecret();
      final Uint8List wrapped = await InviteKeyWrap.wrap(
        groupKey: key,
        secret: secret,
        groupId: 'g-1',
        inviteId: 'i-1',
      );

      final SecretKey? opened = await InviteKeyWrap.unwrap(
        wrapped: wrapped,
        secret: secret,
        groupId: 'g-1',
        inviteId: 'i-1',
      );
      expect(await opened!.extractBytes(), await key.extractBytes());

      expect(
        await InviteKeyWrap.unwrap(
          wrapped: wrapped,
          secret: InviteKeyWrap.randomSecret(),
          groupId: 'g-1',
          inviteId: 'i-1',
        ),
        isNull,
      );
      expect(
        await InviteKeyWrap.unwrap(
          wrapped: wrapped,
          secret: secret,
          groupId: 'g-1',
          inviteId: 'other-invite',
        ),
        isNull,
      );
    });

    test('rings unwrap to their current key', () async {
      final GroupKeyRing ring = GroupKeyRing({
        1: Uint8List.fromList(List.filled(32, 1)),
        2: Uint8List.fromList(List.filled(32, 2)),
      });
      final Uint8List secret = InviteKeyWrap.randomSecret();
      final Uint8List wrapped = await InviteKeyWrap.wrapBytes(
        plaintext: Future.value(ring.encode()),
        secret: secret,
        groupId: 'g-1',
        inviteId: 'i-1',
      );

      final SecretKey? opened = await InviteKeyWrap.unwrap(
        wrapped: wrapped,
        secret: secret,
        groupId: 'g-1',
        inviteId: 'i-1',
      );
      expect(await opened!.extractBytes(), ring.current);
    });

    test('secrets survive link encoding', () {
      final Uint8List secret = InviteKeyWrap.randomSecret();

      expect(
        InviteKeyWrap.decodeSecret(InviteKeyWrap.encodeSecret(secret)),
        secret,
      );
    });
  });

  group('MemberKeys', () {
    test('seals for exactly one recipient', () async {
      final SimpleKeyPair admin =
          await MemberKeys.fromIdentitySeed(List.filled(32, 1));
      final SimpleKeyPair bob =
          await MemberKeys.fromIdentitySeed(List.filled(32, 2));
      final SimpleKeyPair eve =
          await MemberKeys.fromIdentitySeed(List.filled(32, 3));
      final Uint8List bobPub = await MemberKeys.publicKeyBytes(bob);
      final List<int> plaintext = utf8.encode('ring-bytes');

      final Uint8List sealed = await MemberKeys.seal(
        plaintext: plaintext,
        sender: admin,
        recipientPublicKey: bobPub,
        groupId: 'g-1',
        recipientPeerId: 'bob',
      );

      expect(
        await MemberKeys.open(
          sealed: sealed,
          recipient: bob,
          groupId: 'g-1',
          recipientPeerId: 'bob',
        ),
        plaintext,
      );
      expect(
        await MemberKeys.open(
          sealed: sealed,
          recipient: eve,
          groupId: 'g-1',
          recipientPeerId: 'eve',
        ),
        isNull,
      );
      expect(
        await MemberKeys.open(
          sealed: Uint8List.fromList([0, 1, 2]),
          recipient: bob,
          groupId: 'g-1',
          recipientPeerId: 'bob',
        ),
        isNull,
      );
    });

    test('rings encode, decode and accept bare keys', () {
      final GroupKeyRing ring = GroupKeyRing({
        1: Uint8List.fromList(List.filled(32, 1)),
        2: Uint8List.fromList(List.filled(32, 2)),
      });

      expect(GroupKeyRing.decode(ring.encode()), ring);
      expect(ring.current, Uint8List.fromList(List.filled(32, 2)));
      expect(ring.currentVersion, 2);
      expect(ring[1]!.first, 1);
      expect(ring[9], isNull);

      final GroupKeyRing bare = GroupKeyRing.decode(
        List.filled(32, 7),
      )!;
      expect(bare.currentVersion, 1);
      expect(GroupKeyRing.decode([1, 2, 3]), isNull);
      expect(ring == GroupKeyRing.decode(ring.encode()), isTrue);
      expect(ring.hashCode, GroupKeyRing.decode(ring.encode()).hashCode);
    });
  });
}
