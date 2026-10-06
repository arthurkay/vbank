import 'package:cryptography/cryptography.dart';

/// Ed25519 signing and verification.
abstract final class SigningService {
  /// The signature primitive.
  static final _algorithm = Ed25519();

  /// Signs [data] with [keyPair].
  static Future<Signature> sign(
    List<int> data,
    SimpleKeyPair keyPair,
  ) =>
      _algorithm.sign(data, keyPair: keyPair);

  /// Verifies [signatureBytes] over [data] against [publicKey].
  ///
  /// The public key comes from the caller (the member's stored key), never
  /// from whatever the sender attached. Returns false instead of throwing.
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

  /// Verifies against raw public-key bytes as stored in the database.
  static Future<bool> verifyWithBytes(
    List<int> data,
    List<int> signatureBytes,
    List<int> publicKeyBytes,
  ) =>
      verify(
        data,
        signatureBytes,
        SimplePublicKey(publicKeyBytes, type: KeyPairType.ed25519),
      );

  /// Generates a fresh identity key pair.
  static Future<SimpleKeyPair> generateKeyPair() => _algorithm.newKeyPair();

  /// Rebuilds a key pair from its 32-byte seed (as persisted locally).
  static Future<SimpleKeyPair> keyPairFromSeed(List<int> seed) =>
      _algorithm.newKeyPairFromSeed(seed);

  /// Extracts the 32-byte seed so the key pair can be persisted. The seed
  /// lives in the platform keystore, never in the database.
  static Future<List<int>> extractSeed(SimpleKeyPair keyPair) =>
      keyPair.extractPrivateKeyBytes();

  /// Extracts the raw public-key bytes for roster storage.
  static Future<List<int>> extractPublicKeyBytes(SimpleKeyPair keyPair) async {
    final SimplePublicKey publicKey = await keyPair.extractPublicKey();
    return publicKey.bytes;
  }
}
