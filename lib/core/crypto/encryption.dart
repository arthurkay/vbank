import 'package:cryptography/cryptography.dart';

class EncryptionService {
  static final _algorithm = Xchacha20.poly1305Aead();

  /// XChaCha20-Poly1305 encrypt. [aad] (associated authenticated data) is not
  /// encrypted but is bound into the MAC, so cleartext headers such as the
  /// group id cannot be swapped without detection.
  static Future<EncryptedData> encrypt(
    List<int> plaintext,
    SecretKey groupKey, {
    List<int> aad = const [],
  }) async {
    final secretBox = await _algorithm.encrypt(
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

  /// Throws [SecretBoxAuthenticationError] on a wrong key, tampered
  /// ciphertext or mismatched [aad].
  static Future<List<int>> decrypt(
    EncryptedData encrypted,
    SecretKey groupKey, {
    List<int> aad = const [],
  }) async {
    final secretBox = SecretBox(
      encrypted.ciphertext,
      nonce: encrypted.nonce,
      mac: Mac(encrypted.mac),
    );
    return await _algorithm.decrypt(secretBox, secretKey: groupKey, aad: aad);
  }
}

class EncryptedData {
  final List<int> ciphertext;
  final List<int> nonce;
  final List<int> mac;

  const EncryptedData({
    required this.ciphertext,
    required this.nonce,
    required this.mac,
  });

  Map<String, dynamic> toJson() => {
    'ciphertext': ciphertext,
    'nonce': nonce,
    'mac': mac,
  };

  factory EncryptedData.fromJson(Map<String, dynamic> json) => EncryptedData(
    ciphertext: (json['ciphertext'] as List).cast<int>(),
    nonce: (json['nonce'] as List).cast<int>(),
    mac: (json['mac'] as List).cast<int>(),
  );
}
