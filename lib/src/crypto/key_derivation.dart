import 'dart:convert';
import 'dart:isolate';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Key derivation. Two rules:
///
/// * Low-entropy human secrets (PINs, passphrases) go through PBKDF2 with a
///   unique salt — never bare HKDF, which brute-forces trivially.
/// * High-entropy secrets (group keys, device secrets) expand through HKDF.
abstract final class KeyDerivation {
  /// Key length in bytes throughout.
  static const int keyLength = 32;

  /// PBKDF2 work factor for user secrets: deliberately slow to make offline
  /// brute force of a short PIN costly.
  static const int pbkdf2Iterations = 100000;

  /// Salt length for user-secret derivation.
  static const int saltLength = 16;

  /// Random bytes for salts and nonces.
  static List<int> randomBytes([int length = saltLength]) {
    final Random rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Stretches a low-entropy [passphrase] with a random [salt]. The salt
  /// must be stored alongside the ciphertext.
  ///
  /// PBKDF2 is pure Dart and takes seconds on a phone, so it runs in a
  /// background isolate to keep the UI responsive.
  static Future<SecretKey> deriveFromPassphrase(
    String passphrase,
    List<int> salt, {
    int iterations = pbkdf2Iterations,
  }) async {
    final List<int> password = utf8.encode(passphrase);
    final List<int> saltCopy = List<int>.from(salt);
    final List<int> bytes = await Isolate.run(
      () => _pbkdf2(password, saltCopy, iterations, keyLength * 8),
    );
    return SecretKey(bytes);
  }

  static Future<List<int>> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int bits,
  ) async {
    final DartPbkdf2 pbkdf2 = DartPbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: bits,
      // Already off the UI isolate; no need to yield to an event loop.
      pauseFrequency: 1 << 30,
    );
    final SecretKey key = await pbkdf2.deriveKey(
      secretKey: SecretKey(password),
      nonce: salt,
    );
    return key.extractBytes();
  }

  /// The group symmetric key from the shared group passphrase.
  ///
  /// A human passphrase is low-entropy, so it is stretched with PBKDF2. The
  /// salt is the group id — public, unique per group and known to every
  /// joiner — so all members derive the same key while identical
  /// passphrases in different groups yield different keys.
  static Future<SecretKey> deriveGroupKeyFromPassphrase(
    String passphrase,
    String groupId, {
    int iterations = pbkdf2Iterations,
  }) =>
      deriveFromPassphrase(
        passphrase.trim(),
        utf8.encode('vbank-group:$groupId'),
        iterations: iterations,
      );

  /// HKDF expansion of an already-high-entropy secret. NOT for PINs — use
  /// [deriveFromPassphrase] for those.
  static Future<SecretKey> deriveGroupKey(String secret) async {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: keyLength);
    return hkdf.deriveKey(
      secretKey: SecretKey(secret.codeUnits),
      nonce: List.filled(16, 0),
    );
  }

  /// The local database key: the group key mixed with the device secret, so
  /// a stolen database file alone decrypts nothing.
  static Future<SecretKey> deriveLocalDbKey(
    SecretKey groupKey,
    List<int> deviceSecret,
  ) async {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: keyLength);
    final List<int> groupKeyBytes = await groupKey.extractBytes();
    final SecretKey inputKey = SecretKey([...groupKeyBytes, ...deviceSecret]);
    return hkdf.deriveKey(
      secretKey: inputKey,
      nonce: List.filled(16, 0),
    );
  }
}
