import 'package:cryptography/cryptography.dart';

/// XChaCha20-Poly1305 through `package:cryptography`.
abstract final class EncryptionService {
  /// The AEAD primitive.
  static final _algorithm = Xchacha20.poly1305Aead();

  /// Encrypts [plaintext]. [aad] (associated data) is not encrypted but is
  /// bound into the MAC, so cleartext headers such as the group id cannot
  /// be swapped without detection.
  static Future<EncryptedData> encrypt(
    List<int> plaintext,
    SecretKey groupKey, {
    List<int> aad = const [],
  }) async {
    final SecretBox secretBox = await _algorithm.encrypt(
      plaintext,
      secretKey: groupKey,
      aad: aad,
    );
    return EncryptedData(
      ciphertext: secretBox.cipherText,
      nonce: secretBox.nonce,
      mac: secretBox.mac.bytes,
    );
  }

  /// Decrypts [encrypted]. Throws [SecretBoxAuthenticationError] on a wrong
  /// key, tampered ciphertext or mismatched [aad].
  static Future<List<int>> decrypt(
    EncryptedData encrypted,
    SecretKey groupKey, {
    List<int> aad = const [],
  }) async {
    final SecretBox secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );
    return _algorithm.decrypt(secretBox, secretKey: groupKey, aad: aad);
  }
}

/// The three parts of one AEAD encryption.
final class EncryptedData {
  /// Encrypted bytes.
  final List<int> ciphertext;

  /// Per-message nonce.
  final List<int> nonce;

  /// Authentication tag.
  final List<int> mac;

  /// Creates encrypted data.
  const EncryptedData({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is EncryptedData &&
          _equal(ciphertext, other.ciphertext) &&
          _equal(nonce, other.nonce) &&
          _equal(mac, other.mac);

  @override
  int get hashCode => Object.hash(
        Object.hashAll(ciphertext),
        Object.hashAll(nonce),
        Object.hashAll(mac),
      );

  static bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }
}
