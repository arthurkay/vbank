import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/crypto/encryption.dart';
import 'package:vbank/core/crypto/identity.dart';
import 'package:vbank/core/crypto/key_derivation.dart';
import 'package:vbank/core/crypto/signing.dart';
import 'package:vbank/services/backup_service.dart';
import 'package:vbank/services/transaction_service.dart';
import 'package:vbank/models/transaction.dart';

void main() {
  group('SigningService', () {
    test('verify succeeds with the signer public key', () async {
      final kp = await SigningService.generateKeyPair();
      final pub = await SigningService.extractPublicKeyBytes(kp);
      final sig = await SigningService.sign(utf8.encode('hello'), kp);

      expect(await SigningService.verifyWithBytes(utf8.encode('hello'), sig.bytes, pub), isTrue);
    });

    test('verify fails with a different public key (attacker-supplied key is ignored)', () async {
      final signer = await SigningService.generateKeyPair();
      final other = await SigningService.generateKeyPair();
      final otherPub = await SigningService.extractPublicKeyBytes(other);
      final sig = await SigningService.sign(utf8.encode('hello'), signer);

      expect(await SigningService.verifyWithBytes(utf8.encode('hello'), sig.bytes, otherPub), isFalse);
    });

    test('verify fails on tampered data', () async {
      final kp = await SigningService.generateKeyPair();
      final pub = await SigningService.extractPublicKeyBytes(kp);
      final sig = await SigningService.sign(utf8.encode('amount=10'), kp);

      expect(await SigningService.verifyWithBytes(utf8.encode('amount=100'), sig.bytes, pub), isFalse);
    });

    test('key pair round-trips through its seed', () async {
      final kp = await SigningService.generateKeyPair();
      final seed = await SigningService.extractSeed(kp);
      final rebuilt = await SigningService.keyPairFromSeed(seed);

      expect(
        await SigningService.extractPublicKeyBytes(rebuilt),
        equals(await SigningService.extractPublicKeyBytes(kp)),
      );
      final sig = await SigningService.sign(utf8.encode('x'), rebuilt);
      final pub = await SigningService.extractPublicKeyBytes(kp);
      expect(await SigningService.verifyWithBytes(utf8.encode('x'), sig.bytes, pub), isTrue);
    });
  });

  group('IdentityManager', () {
    test('peer id is deterministic for the same public key', () {
      final pub = List<int>.generate(32, (i) => i);
      expect(IdentityManager.generatePeerId(pub), IdentityManager.generatePeerId(pub));
      expect(IdentityManager.generatePeerId(pub), startsWith('vbank_'));
    });

    test('different public keys give different peer ids', () {
      final a = List<int>.generate(32, (i) => i);
      final b = List<int>.generate(32, (i) => i + 1);
      expect(IdentityManager.generatePeerId(a), isNot(IdentityManager.generatePeerId(b)));
    });

    test('createIdentity returns a usable seed matching the public key', () async {
      final g = await IdentityManager.createIdentity('Test');
      expect(g.privateKeySeed.length, 32);
      final rebuilt = await SigningService.keyPairFromSeed(g.privateKeySeed);
      expect(
        await SigningService.extractPublicKeyBytes(rebuilt),
        equals(g.identity.publicKey),
      );
      expect(g.identity.peerId, IdentityManager.generatePeerId(g.identity.publicKey));
    });
  });

  group('TransactionService signatures', () {
    test('verifySignature matches createTransaction payload', () async {
      final kp = await SigningService.generateKeyPair();
      final pub = await SigningService.extractPublicKeyBytes(kp);
      final unsigned = Transaction(
        id: 'tx1',
        groupId: 'g1',
        fromPeerId: 'a',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 50,
        timestamp: DateTime.utc(2026),
        sequenceNumber: 3,
        senderSignature: Uint8List(0),
        authorPeerId: 'admin',
      );
      final sig = await SigningService.sign(TransactionService.signingPayload(unsigned), kp);
      final tx = Transaction(
        id: 'tx1',
        groupId: 'g1',
        fromPeerId: 'a',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 50,
        timestamp: DateTime.utc(2026),
        sequenceNumber: 3,
        senderSignature: Uint8List.fromList(sig.bytes),
        authorPeerId: 'admin',
      );

      expect(await TransactionService().verifySignature(tx, pub), isTrue);

      final forged = Transaction(
        id: tx.id,
        groupId: tx.groupId,
        fromPeerId: tx.fromPeerId,
        toPeerId: tx.toPeerId,
        type: tx.type,
        amount: 5000,
        timestamp: tx.timestamp,
        sequenceNumber: tx.sequenceNumber,
        senderSignature: tx.senderSignature,
        authorPeerId: tx.authorPeerId,
      );
      expect(await TransactionService().verifySignature(forged, pub), isFalse);
    });
  });

  group('Backup envelope', () {
    test('encrypt/decrypt round-trip keeps nonce, MAC and salt', () async {
      final salt = KeyDerivation.randomSalt();
      final key = await KeyDerivation.deriveFromPassphrase('1234', salt, iterations: 1000);
      final plaintext = utf8.encode('secret payload');
      final enc = await EncryptionService.encrypt(plaintext, key);

      final envelope = BackupEnvelope(
        iterations: 1000,
        salt: salt,
        nonce: enc.nonce,
        mac: enc.mac,
        ciphertext: enc.ciphertext,
      ).encode();

      final decoded = BackupEnvelope.tryDecode(envelope);
      expect(decoded, isNotNull);
      expect(decoded!.nonce, enc.nonce);
      expect(decoded.mac, enc.mac);
      expect(decoded.salt, salt);

      final key2 = await KeyDerivation.deriveFromPassphrase('1234', decoded.salt, iterations: decoded.iterations);
      final out = await EncryptionService.decrypt(
        EncryptedData(ciphertext: decoded.ciphertext, nonce: decoded.nonce, mac: decoded.mac),
        key2,
      );
      expect(utf8.decode(out), 'secret payload');
    });

    test('wrong PIN fails authentication', () async {
      final salt = KeyDerivation.randomSalt();
      final key = await KeyDerivation.deriveFromPassphrase('1234', salt, iterations: 1000);
      final enc = await EncryptionService.encrypt(utf8.encode('x'), key);
      final wrong = await KeyDerivation.deriveFromPassphrase('9999', salt, iterations: 1000);

      expect(
        () => EncryptionService.decrypt(
          EncryptedData(ciphertext: enc.ciphertext, nonce: enc.nonce, mac: enc.mac),
          wrong,
        ),
        throwsA(anything),
      );
    });

    test('legacy ciphertext-only blob is rejected, not misinterpreted', () {
      expect(BackupEnvelope.tryDecode(Uint8List.fromList([1, 2, 3, 4])), isNull);
    });

    test('same PIN yields different keys with different salts', () async {
      final a = await KeyDerivation.deriveFromPassphrase('1234', KeyDerivation.randomSalt(), iterations: 1000);
      final b = await KeyDerivation.deriveFromPassphrase('1234', KeyDerivation.randomSalt(), iterations: 1000);
      expect(await a.extractBytes(), isNot(equals(await b.extractBytes())));
    });
  });
}
