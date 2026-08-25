import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

class KeyDerivation {
  static const int _keyLength = 32;

  /// PBKDF2 parameters for user-chosen secrets (PINs / passphrases). These
  /// are deliberately slow to make offline brute force of a short PIN costly.
  static const int pbkdf2Iterations = 100000;
  static const int saltLength = 16;

  static List<int> randomSalt([int length = saltLength]) {
    final rng = Random.secure();
    return List<int>.generate(length, (_) => rng.nextInt(256));
  }

  /// Derives a key from a low-entropy user secret (PIN/passphrase) with a
  /// random [salt]. The salt must be stored alongside the ciphertext.
  ///
  /// PBKDF2 is pure Dart here and takes seconds on a phone, so it runs in a
  /// background isolate to keep the UI responsive.
  static Future<SecretKey> deriveFromPassphrase(
    String passphrase,
    List<int> salt, {
    int iterations = pbkdf2Iterations,
  }) async {
    final password = utf8.encode(passphrase);
    final saltCopy = List<int>.from(salt);
    final bytes = await Isolate.run(
      () => _pbkdf2(password, saltCopy, iterations, _keyLength * 8),
    );
    return SecretKey(bytes);
  }

  static Future<List<int>> _pbkdf2(
    List<int> password,
    List<int> salt,
    int iterations,
    int bits,
  ) async {
    final pbkdf2 = DartPbkdf2(
      macAlgorithm: Hmac.sha256(),
      iterations: iterations,
      bits: bits,
      // We're already off the UI isolate; no need to yield to an event loop.
      pauseFrequency: 1 << 30,
    );
    final key = await pbkdf2.deriveKey(
      secretKey: SecretKey(password),
      nonce: salt,
    );
    return key.extractBytes();
  }

  /// Group symmetric key from the shared group passphrase (DESIGN_PLAN §12).
  ///
  /// Deviation from the plan's bare HKDF: a human passphrase is low-entropy,
  /// so it is stretched with PBKDF2. The salt is the group id — public, unique
  /// per group, and known to every joiner — so all members derive the same
  /// key while identical passphrases in different groups yield different keys.
  static Future<SecretKey> deriveGroupKeyFromPassphrase(
    String passphrase,
    String groupId, {
    int iterations = pbkdf2Iterations,
  }) {
    return deriveFromPassphrase(
      passphrase.trim(),
      utf8.encode('vbank-group:$groupId'),
      iterations: iterations,
    );
  }

  /// HKDF expansion of an already-high-entropy secret (e.g. a group key).
  /// NOT suitable for PINs — use [deriveFromPassphrase] for those.
  static Future<SecretKey> deriveGroupKey(String secret) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _keyLength);
    return await hkdf.deriveKey(
      secretKey: SecretKey(secret.codeUnits),
      nonce: List.filled(16, 0),
    );
  }

  static Future<SecretKey> deriveLocalDbKey(
    SecretKey groupKey,
    List<int> deviceSecret,
  ) async {
    final hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: _keyLength);
    final groupKeyBytes = await groupKey.extractBytes();
    final inputKey = SecretKey([...groupKeyBytes, ...deviceSecret]);
    return await hkdf.deriveKey(
      secretKey: inputKey,
      nonce: List.filled(16, 0),
    );
  }

  static Future<List<int>> deriveKeyBytes(String passphrase) async {
    final key = await deriveGroupKey(passphrase);
    return await key.extractBytes();
  }
}
