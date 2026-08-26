import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// A random 32-byte secret generated once per install and kept in the
/// platform secure store (Android Keystore-backed EncryptedSharedPreferences /
/// iOS Keychain). It never leaves the device and is not included in backups.
///
/// DESIGN_PLAN §12: used to derive the local database encryption key.
///
/// Desktop caveat: on Linux the platform store is the Secret Service (libsecret
/// + a running keyring). Where none is available — a minimal desktop, a server
/// session, CI — we fall back to a `0600` file in the app support directory.
/// That is weaker than a keyring (a process running as the same user can read
/// it) but it keeps the database encrypted at rest, and the fallback is only
/// used when the keyring itself refuses.
class DeviceSecret {
  static const _key = 'vbank.device_secret.v1';
  static const _storage = FlutterSecureStorage(
    iOptions: IOSOptions(accessibility: KeychainAccessibility.first_unlock_this_device),
  );

  static Uint8List? _cached;

  /// How long to wait for the platform keyring before using the file fallback.
  static const _keyringTimeout = Duration(seconds: 3);

  /// Returns the device secret, creating it on first use.
  static Future<Uint8List> get() async {
    final cached = _cached;
    if (cached != null) return cached;

    String? stored;
    var keyringUsable = true;
    try {
      // On Linux the read goes over D-Bus to a Secret Service. With no keyring
      // running the call can block instead of failing, which would hang start-up
      // — so bound it and fall back to the file.
      stored = await _storage.read(key: _key).timeout(_keyringTimeout);
    } catch (_) {
      keyringUsable = false; // no Secret Service, keyring locked, or timed out
    }
    stored ??= keyringUsable ? null : await _readFallback();

    if (stored != null) {
      final bytes = Uint8List.fromList(base64Decode(stored));
      _cached = bytes;
      return bytes;
    }

    final rng = Random.secure();
    final bytes = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    final encoded = base64Encode(bytes);
    if (keyringUsable) {
      try {
        await _storage.write(key: _key, value: encoded).timeout(_keyringTimeout);
      } catch (_) {
        keyringUsable = false;
      }
    }
    if (!keyringUsable) await _writeFallback(encoded);
    _cached = bytes;
    return bytes;
  }

  static Future<File> _fallbackFile() async {
    final dir = await getApplicationSupportDirectory();
    return File(p.join(dir.path, 'device_secret'));
  }

  static Future<String?> _readFallback() async {
    try {
      final file = await _fallbackFile();
      if (!await file.exists()) return null;
      final value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeFallback(String encoded) async {
    final file = await _fallbackFile();
    await file.parent.create(recursive: true);
    await file.writeAsString(encoded, flush: true);
    if (!Platform.isWindows) {
      // Owner read/write only.
      await Process.run('chmod', ['600', file.path]);
    }
  }

  /// Test hook.
  static void overrideForTests(Uint8List? secret) => _cached = secret;
}
