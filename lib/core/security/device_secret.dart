import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// A random 32-byte secret generated once per install and kept in the
/// platform secure store (Android Keystore-backed EncryptedSharedPreferences /
/// iOS Keychain). It never leaves the device and is not included in backups.
///
/// DESIGN_PLAN §12: used to derive the local database encryption key.
class DeviceSecret {
  static const _key = 'vbank.device_secret.v1';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static Uint8List? _cached;

  /// Returns the device secret, creating it on first use.
  static Future<Uint8List> get() async {
    final cached = _cached;
    if (cached != null) return cached;

    final stored = await _storage.read(key: _key);
    if (stored != null) {
      final bytes = Uint8List.fromList(base64Decode(stored));
      _cached = bytes;
      return bytes;
    }

    final rng = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    await _storage.write(key: _key, value: base64Encode(bytes));
    _cached = bytes;
    return bytes;
  }

  /// Test hook.
  static void overrideForTests(Uint8List? secret) => _cached = secret;
}
