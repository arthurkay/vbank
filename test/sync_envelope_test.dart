import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:vbank/core/crypto/encryption.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/codec/wire_codec.dart';
import 'package:vbank/core/crypto/sync_envelope.dart';
import 'package:vbank/services/group_key_service.dart';

void main() {
  group('SyncEnvelope', () {
    const groupId = 'g-1234';
    final payload = {'id': 'tx1', 'amount': 50.0, 'note': 'weekly'};

    test('seal → decode → open round-trips with the right key', () async {
      final key = await GroupKeyService.deriveKey('chilenje-savings-2026', groupId);
      final bytes = await SyncEnvelope.seal(
        type: SyncPayloadType.transaction,
        groupId: groupId,
        plaintextJson: payload,
        groupKey: key,
      );

      final env = SyncEnvelope.tryDecode(bytes)!;
      expect(env.type, SyncPayloadType.transaction);
      expect(env.groupId, groupId);
      expect(await env.open(key), payload);
    });

    test('the plaintext is not visible in the sealed bytes', () async {
      final key = await GroupKeyService.deriveKey('chilenje-savings-2026', groupId);
      final bytes = await SyncEnvelope.seal(
        type: SyncPayloadType.transaction,
        groupId: groupId,
        plaintextJson: payload,
        groupKey: key,
      );
      final text = utf8.decode(bytes, allowMalformed: true);
      expect(text, isNot(contains('tx1')));
      expect(text, isNot(contains('weekly')));
      // header is cleartext CBOR, body is ciphertext
      expect(text, contains('transaction'));
    });

    test('wrong passphrase fails to open', () async {
      final right = await GroupKeyService.deriveKey('chilenje-savings-2026', groupId);
      final wrong = await GroupKeyService.deriveKey('chilenje-savings-2025', groupId);
      final bytes = await SyncEnvelope.seal(
        type: SyncPayloadType.transaction,
        groupId: groupId,
        plaintextJson: payload,
        groupKey: right,
      );
      final env = SyncEnvelope.tryDecode(bytes)!;
      expect(() => env.open(wrong), throwsA(isA<EnvelopeAuthException>()));
    });

    test('same passphrase on two devices derives the same key', () async {
      final a = await GroupKeyService.deriveKey('village-savings-2026', groupId);
      final b = await GroupKeyService.deriveKey('  village-savings-2026 ', groupId);
      expect(await a.extractBytes(), await b.extractBytes());
    });

    test('tampering with the cleartext header (group id) is detected', () async {
      final key = await GroupKeyService.deriveKey('chilenje-savings-2026', groupId);
      final bytes = await SyncEnvelope.seal(
        type: SyncPayloadType.transaction,
        groupId: groupId,
        plaintextJson: payload,
        groupKey: key,
      );
      final json = WireCodec.tryDecodeMap(bytes)!;
      json['groupId'] = 'g-other';
      final tampered = SyncEnvelope.tryDecode(WireCodec.encode(json))!;
      expect(() => tampered.open(key), throwsA(isA<EnvelopeAuthException>()));
    });

    test('tampering with the type is detected', () async {
      final key = await GroupKeyService.deriveKey('chilenje-savings-2026', groupId);
      final bytes = await SyncEnvelope.seal(
        type: SyncPayloadType.transaction,
        groupId: groupId,
        plaintextJson: payload,
        groupKey: key,
      );
      final json = WireCodec.tryDecodeMap(bytes)!;
      json['type'] = SyncPayloadType.groupSnapshot.name;
      final tampered = SyncEnvelope.tryDecode(WireCodec.encode(json))!;
      expect(() => tampered.open(key), throwsA(isA<EnvelopeAuthException>()));
    });

    test('non-envelope bytes decode to null', () {
      expect(SyncEnvelope.tryDecode(utf8.encode('{"id":"tx1","amount":50}')), isNull);
      expect(SyncEnvelope.tryDecode(Uint8List.fromList([0, 1, 2])), isNull);
      expect(SyncEnvelope.tryDecode(WireCodec.encode({'id': 'tx1'})), isNull);
    });

    test('legacy v1 JSON/base64 envelopes still decode', () async {
      final key = await GroupKeyService.deriveKey('chilenje-savings-2026', groupId);
      final enc = await EncryptionService.encrypt(
        utf8.encode(jsonEncode(payload)), key,
        aad: utf8.encode('vbank:1:transaction:$groupId'));
      final legacy = utf8.encode(jsonEncode({
        'v': 1, 'type': 'transaction', 'groupId': groupId,
        'nonce': base64Encode(enc.nonce), 'mac': base64Encode(enc.mac), 'ciphertext': base64Encode(enc.ciphertext),
      }));
      final env = SyncEnvelope.tryDecode(legacy)!;
      expect(env.version, 1);
      expect(await env.open(key), payload);
    });

    test('CBOR wire format round-trips bytes and nested maps', () {
      final v = {'a': Uint8List.fromList([1, 2, 3]), 'b': [1, 2], 'c': {'d': 1.5, 'e': null, 'f': true}};
      final back = WireCodec.tryDecodeMap(WireCodec.encode(v))!;
      expect((back['a'] as List).cast<int>(), [1, 2, 3]);
      expect(back['b'], [1, 2]);
      expect((back['c'] as Map<String, dynamic>)['d'], 1.5);
      expect((back['c'] as Map<String, dynamic>)['e'], isNull);
    });

    test('each seal uses a fresh nonce', () async {
      final key = SecretKey(List<int>.filled(32, 7));
      final a = SyncEnvelope.tryDecode(await SyncEnvelope.seal(
        type: SyncPayloadType.transaction, groupId: groupId, plaintextJson: payload, groupKey: key))!;
      final b = SyncEnvelope.tryDecode(await SyncEnvelope.seal(
        type: SyncPayloadType.transaction, groupId: groupId, plaintextJson: payload, groupKey: key))!;
      expect(a.data.nonce, isNot(equals(b.data.nonce)));
      expect(a.data.nonce.length, 24);
    });
  });

  group('GroupKeyService.validatePassphrase', () {
    test('rejects short passphrases', () {
      expect(GroupKeyService.validatePassphrase('short'), isNotNull);
      expect(GroupKeyService.validatePassphrase('   1234   '), isNotNull);
    });
    test('accepts 8+ chars', () {
      expect(GroupKeyService.validatePassphrase('village-2026'), isNull);
    });
  });
}
