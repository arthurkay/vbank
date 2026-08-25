import 'package:cryptography/cryptography.dart';

class SigningService {
  static final _algorithm = Ed25519();

  static Future<Signature> sign(
    List<int> data,
    SimpleKeyPair keyPair,
  ) async {
    return await _algorithm.sign(data, keyPair: keyPair);
  }

  /// Verifies [signatureBytes] over [data] against [publicKey].
  ///
  /// The public key is taken from the caller (i.e. the member's stored key),
  /// never from whatever key the sender attached to the signature.
  static Future<bool> verify(
    List<int> data,
    List<int> signatureBytes,
    SimplePublicKey publicKey,
  ) async {
    try {
      return await _algorithm.verify(
        data,
        signature: Signature(signatureBytes, publicKey: publicKey),
      );
    } catch (_) {
      return false;
    }
  }

  /// Convenience for raw public-key bytes (as stored in the DB).
  static Future<bool> verifyWithBytes(
    List<int> data,
    List<int> signatureBytes,
    List<int> publicKeyBytes,
  ) {
    return verify(
      data,
      signatureBytes,
      SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
    );
  }

  static Future<SimpleKeyPair> generateKeyPair() async {
    return await _algorithm.newKeyPair();
  }

  /// Rebuilds a key pair from its 32-byte Ed25519 seed (as persisted locally).
  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) async {
    return await _algorithm.newKeyPairFromSeed(seed);
  }

  /// Extracts the 32-byte seed so the key pair can be persisted.
  static Future<List<int>> extractSeed(SimpleKeyPair keyPair) async {
    return await keyPair.extractPrivateKeyBytes();
  }

  static Future<List<int>> extractPublicKeyBytes(SimpleKeyPair keyPair) async {
    final publicKey = await keyPair.extractPublicKey();
    return publicKey.bytes;
  }
}
