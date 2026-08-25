import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/crypto/key_derivation.dart';
import '../core/storage/group_key_dao.dart';

class MissingGroupKeyException implements Exception {
  final String groupId;
  const MissingGroupKeyException(this.groupId);
  @override
  String toString() =>
      'No group key for $groupId — enter the group passphrase to sync this group';
}

/// Manages the per-group symmetric key (DESIGN_PLAN §12).
///
///     Group passphrase ──PBKDF2(salt = group id)──► 32-byte group key
///
/// The passphrase itself is never stored; only the derived key is, so that
/// every member who knows the passphrase derives the *same* key on their own
/// device and can decrypt the group's IPFS payloads.
class GroupKeyService {
  final GroupKeyDao _dao;
  final Map<String, SecretKey> _cache = {};

  GroupKeyService({GroupKeyDao? dao}) : _dao = dao ?? GroupKeyDao();

  static const minPassphraseLength = 8;

  static String? validatePassphrase(String passphrase) {
    if (passphrase.trim().length < minPassphraseLength) {
      return 'Group passphrase must be at least $minPassphraseLength characters';
    }
    return null;
  }

  /// Derives the group key for [groupId] from the shared passphrase.
  /// Runs PBKDF2 off the UI isolate; takes ~1 s on a low-end phone.
  static Future<SecretKey> deriveKey(String passphrase, String groupId) {
    return KeyDerivation.deriveGroupKeyFromPassphrase(passphrase, groupId);
  }

  /// Derives the key from [passphrase] and stores it for [groupId].
  Future<SecretKey> setFromPassphrase(String groupId, String passphrase) async {
    final key = await deriveKey(passphrase, groupId);
    await setKey(groupId, key);
    return key;
  }

  Future<void> setKey(String groupId, SecretKey key) async {
    final bytes = Uint8List.fromList(await key.extractBytes());
    await _dao.upsert(groupId, bytes);
    _cache[groupId] = key;
  }

  Future<SecretKey?> getKey(String groupId) async {
    final cached = _cache[groupId];
    if (cached != null) return cached;
    final bytes = await _dao.get(groupId);
    if (bytes == null) return null;
    final key = SecretKey(bytes);
    _cache[groupId] = key;
    return key;
  }

  Future<SecretKey> requireKey(String groupId) async {
    final key = await getKey(groupId);
    if (key == null) throw MissingGroupKeyException(groupId);
    return key;
  }

  Future<bool> hasKey(String groupId) async => (await getKey(groupId)) != null;

  Future<void> removeKey(String groupId) async {
    _cache.remove(groupId);
    await _dao.delete(groupId);
  }

  /// Raw key material for backups. Restore with [importAll].
  Future<Map<String, Uint8List>> exportAll() => _dao.getAll();

  Future<void> importAll(Map<String, Uint8List> keys) async {
    for (final e in keys.entries) {
      await _dao.upsert(e.key, e.value);
      _cache[e.key] = SecretKey(e.value);
    }
  }
}
