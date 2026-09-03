import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../core/crypto/key_derivation.dart';
import '../core/crypto/member_keys.dart';
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
  /// A fresh random data key for a new group. Members receive it through
  /// invite links (InviteKeyWrap), never through a shared passphrase.
  Future<SecretKey> setRandom(String groupId) async {
    final rng = Random.secure();
    final key = SecretKey(List<int>.generate(32, (_) => rng.nextInt(256)));
    await setKey(groupId, key);
    return key;
  }

  Future<SecretKey> setFromPassphrase(String groupId, String passphrase) async {
    final key = await deriveKey(passphrase, groupId);
    await setKey(groupId, key);
    return key;
  }

  /// Sets the *current* key (version 1 when the group has no ring yet).
  Future<void> setKey(String groupId, SecretKey key) async {
    final bytes = Uint8List.fromList(await key.extractBytes());
    await _dao.upsert(groupId, bytes);
    final versions = await _dao.versions(groupId);
    if (versions.isEmpty) await _dao.upsertVersion(groupId, 1, bytes);
    _cache[groupId] = key;
    _ringCache.remove(groupId);
  }

  // --- key ring / rotation ---------------------------------------------------

  final Map<String, GroupKeyRing> _ringCache = {};

  /// Every key version of [groupId], oldest first; null when we hold no key.
  Future<GroupKeyRing?> ring(String groupId) async {
    final cached = _ringCache[groupId];
    if (cached != null) return cached;
    var versions = await _dao.versions(groupId);
    if (versions.isEmpty) {
      final current = await _dao.get(groupId);
      if (current == null) return null;
      versions = {1: current};
      await _dao.upsertVersion(groupId, 1, current);
    }
    return _ringCache[groupId] = GroupKeyRing(versions);
  }

  Future<int> currentVersion(String groupId) async => (await ring(groupId))?.currentVersion ?? 1;

  /// Key for a specific envelope version; null if we never received it.
  Future<SecretKey?> keyFor(String groupId, int version) async {
    if (version <= 1) {
      final r = await ring(groupId);
      final v1 = r?[1];
      return v1 == null ? await getKey(groupId) : SecretKey(v1);
    }
    final bytes = (await ring(groupId))?[version];
    return bytes == null ? null : SecretKey(bytes);
  }

  /// Generates the next key version and makes it current. Records published
  /// from now on use it; members without it cannot read them.
  Future<GroupKeyRing> rotate(String groupId) async {
    final r = await ring(groupId);
    if (r == null) throw MissingGroupKeyException(groupId);
    final rng = Random.secure();
    final next = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    final version = r.currentVersion + 1;
    await _dao.upsertVersion(groupId, version, next);
    await _dao.upsert(groupId, next);
    _cache[groupId] = SecretKey(next);
    _ringCache.remove(groupId);
    return (await ring(groupId))!;
  }

  /// Merges a ring received from an admin (invite wrap or re-key): adds unknown
  /// versions and moves the current key forward, never backward.
  Future<void> importRing(String groupId, GroupKeyRing incoming) async {
    final mine = await ring(groupId);
    for (final e in incoming.keys.entries) {
      if (mine?[e.key] == null) await _dao.upsertVersion(groupId, e.key, e.value);
    }
    if (mine == null || incoming.currentVersion > mine.currentVersion) {
      await _dao.upsert(groupId, incoming.current);
      _cache[groupId] = SecretKey(incoming.current);
    }
    _ringCache.remove(groupId);
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
    _ringCache.remove(groupId);
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
