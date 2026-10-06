import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/key_derivation.dart';
import '../crypto/member_keys.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/repositories.dart';

/// Raw key storage on settings: current key plus every issued version.
///
/// Keys `gkey.cur.<group>` (current bytes), `gkey.vers.<group>` (JSON
/// version list) and `gkey.v.<group>.<version>` (bytes). The database file
/// itself is encrypted, and keys never leave the device except sealed for
/// a member or wrapped for an invite.
final class GroupKeyStore {
  /// Backing settings.
  final SettingsRepository settings;

  /// Creates a key store on [settings].
  GroupKeyStore(this.settings);

  static String _cur(String groupId) => 'gkey.cur.$groupId';
  static String _vers(String groupId) => 'gkey.vers.$groupId';
  static String _at(String groupId, int version) => 'gkey.v.$groupId.$version';

  /// Stores [bytes] as the current key for [groupId]. Leaves the version
  /// list alone: rotations set the new version first, then move current.
  Future<Result<Unit>> setCurrent(String groupId, Uint8List bytes) =>
      settings.set(_cur(groupId), bytes);

  /// The current key bytes, or null.
  Future<Result<Uint8List?>> current(String groupId) =>
      settings.get(_cur(groupId));

  /// Stores [bytes] as [version] of [groupId]'s ring.
  Future<Result<Unit>> setVersion(
    String groupId,
    int version,
    Uint8List bytes,
  ) async {
    final Result<Unit> saved = await settings.set(_at(groupId, version), bytes);
    if (saved.isErr) {
      return saved;
    }
    final Set<int> versions = {...await _versionList(groupId), version};
    final List<int> ordered = versions.toList()..sort();
    return settings.set(
      _vers(groupId),
      Uint8List.fromList(utf8.encode(jsonEncode(ordered))),
    );
  }

  /// Every stored version, oldest first.
  Future<Result<Map<int, Uint8List>>> versions(String groupId) async {
    final Map<int, Uint8List> out = {};
    for (final int v in await _versionList(groupId)) {
      final Result<Uint8List?> bytes = await settings.get(_at(groupId, v));
      if (bytes.isErr) {
        return Err(bytes.failure);
      }
      if (bytes.value != null) {
        out[v] = bytes.value!;
      }
    }
    return Ok(out);
  }

  /// Forgets every key of [groupId].
  Future<Result<Unit>> delete(String groupId) async {
    for (final int v in await _versionList(groupId)) {
      final Result<Unit> removed = await settings.remove(_at(groupId, v));
      if (removed.isErr) {
        return removed;
      }
    }
    final Result<Unit> versRemoved = await settings.remove(_vers(groupId));
    if (versRemoved.isErr) {
      return versRemoved;
    }
    return settings.remove(_cur(groupId));
  }

  /// Every group with a current key, for backups.
  Future<Result<Map<String, Uint8List>>> allCurrent() async {
    final Result<List<String>> keys = await settings.keysWithPrefix(
      'gkey.cur.',
    );
    if (keys.isErr) {
      return Err(keys.failure);
    }
    final Map<String, Uint8List> out = {};
    for (final String key in keys.value) {
      final Result<Uint8List?> bytes = await settings.get(key);
      if (bytes.isErr) {
        return Err(bytes.failure);
      }
      if (bytes.value != null) {
        out[key.substring('gkey.cur.'.length)] = bytes.value!;
      }
    }
    return Ok(out);
  }

  Future<List<int>> _versionList(String groupId) async {
    final Result<Uint8List?> raw = await settings.get(_vers(groupId));
    if (raw.isErr || raw.value == null) {
      return const [];
    }
    try {
      return (jsonDecode(utf8.decode(raw.value!)) as List).cast<int>();
    } catch (_) {
      return const [];
    }
  }
}

/// Per-group symmetric keys: derivation, storage, rotation.
///
/// Passphrases stretch through PBKDF2 (salt = group id); new groups get a
/// random key that travels by invite wrap instead. Rotations append
/// versions; history stays readable through the ring.
final class GroupKeyService {
  /// Raw key storage.
  final GroupKeyStore store;

  /// In-memory caches (keys are SecretKeys: unextractable handles).
  final Map<String, SecretKey> _cache = {};
  final Map<String, GroupKeyRing> _ringCache = {};

  /// Minimum passphrase length.
  static const int minPassphraseLength = 8;

  /// Creates a key service on [store].
  GroupKeyService(this.store);

  /// True when [passphrase] is long enough to stretch.
  static bool isPassphraseValid(String passphrase) =>
      passphrase.trim().length >= minPassphraseLength;

  /// Derives the group key from [passphrase] (PBKDF2, ~1 s on a phone).
  static Future<SecretKey> deriveKey(String passphrase, String groupId) =>
      KeyDerivation.deriveGroupKeyFromPassphrase(passphrase, groupId);

  /// Generates a random current key for a new group.
  Future<Result<SecretKey>> setRandom(String groupId) async {
    final Random rng = Random.secure();
    final SecretKey key = SecretKey(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    final Result<Unit> saved = await setKey(groupId, key);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(key);
  }

  /// Derives from [passphrase] and stores the key for [groupId].
  Future<Result<SecretKey>> setFromPassphrase(
    String groupId,
    String passphrase,
  ) async {
    final SecretKey key = await deriveKey(passphrase, groupId);
    final Result<Unit> saved = await setKey(groupId, key);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(key);
  }

  /// Stores [key] as current (version 1 when the group has no ring yet).
  Future<Result<Unit>> setKey(String groupId, SecretKey key) async {
    final Uint8List bytes = Uint8List.fromList(await key.extractBytes());
    final Result<Unit> current = await store.setCurrent(groupId, bytes);
    if (current.isErr) {
      return current;
    }
    final Result<Map<int, Uint8List>> versions = await store.versions(
      groupId,
    );
    if (versions.isErr) {
      return Err(versions.failure);
    }
    if (versions.value.isEmpty) {
      final Result<Unit> first = await store.setVersion(groupId, 1, bytes);
      if (first.isErr) {
        return first;
      }
    }
    _cache[groupId] = key;
    _ringCache.remove(groupId);
    return const Ok(unit);
  }

  /// Every key version of [groupId], oldest first; null when keyless.
  Future<GroupKeyRing?> ring(String groupId) async {
    final GroupKeyRing? cached = _ringCache[groupId];
    if (cached != null) {
      return cached;
    }
    final Result<Map<int, Uint8List>> stored = await store.versions(groupId);
    Map<int, Uint8List> versions = stored.isOk ? stored.value : {};
    if (versions.isEmpty) {
      final Result<Uint8List?> current = await store.current(groupId);
      if (current.isErr || current.value == null) {
        return null;
      }
      await store.setVersion(groupId, 1, current.value!);
      versions = {1: current.value!};
    }
    final GroupKeyRing ring = GroupKeyRing(versions);
    _ringCache[groupId] = ring;
    return ring;
  }

  /// Highest version held, 1 when keyless (envelopes default there).
  Future<int> currentVersion(String groupId) async =>
      (await ring(groupId))?.currentVersion ?? 1;

  /// Key for an envelope version; null when never received.
  Future<SecretKey?> keyFor(String groupId, int version) async {
    final GroupKeyRing? r = await ring(groupId);
    Uint8List? bytes = r?[version <= 1 ? 1 : version];
    if (bytes == null && version <= 1) {
      final SecretKey? current = await getKey(groupId);
      bytes = current == null
          ? null
          : Uint8List.fromList(await current.extractBytes());
    }
    return bytes == null ? null : SecretKey(bytes);
  }

  /// Generates the next version and makes it current. Records published
  /// from now on use it.
  Future<Result<GroupKeyRing>> rotate(String groupId) async {
    final GroupKeyRing? r = await ring(groupId);
    if (r == null) {
      return Err(NotFoundFailure('groupkey:$groupId'));
    }
    final Random rng = Random.secure();
    final Uint8List next = Uint8List.fromList(
      List<int>.generate(32, (_) => rng.nextInt(256)),
    );
    final int version = r.currentVersion + 1;
    final Result<Unit> stored = await store.setVersion(groupId, version, next);
    if (stored.isErr) {
      return Err(stored.failure);
    }
    final Result<Unit> current = await store.setCurrent(groupId, next);
    if (current.isErr) {
      return Err(current.failure);
    }
    _cache[groupId] = SecretKey(next);
    _ringCache.remove(groupId);
    final GroupKeyRing? rotated = await ring(groupId);
    if (rotated == null) {
      return Err(NotFoundFailure('groupkey:$groupId'));
    }
    return Ok(rotated);
  }

  /// Merges a ring received from an admin: adds unknown versions and moves
  /// the current key forward, never backward.
  Future<Result<Unit>> importRing(
    String groupId,
    GroupKeyRing incoming,
  ) async {
    final GroupKeyRing? mine = await ring(groupId);
    for (final MapEntry<int, Uint8List> e in incoming.keys.entries) {
      if (mine?[e.key] == null) {
        final Result<Unit> stored = await store.setVersion(
          groupId,
          e.key,
          e.value,
        );
        if (stored.isErr) {
          return stored;
        }
      }
    }
    if (mine == null || incoming.currentVersion > mine.currentVersion) {
      final Result<Unit> current = await store.setCurrent(
        groupId,
        incoming.current,
      );
      if (current.isErr) {
        return current;
      }
      _cache[groupId] = SecretKey(incoming.current);
    }
    _ringCache.remove(groupId);
    return const Ok(unit);
  }

  /// Current key bytes, or null when keyless or unreadable (both mean the
  /// passphrase must be entered).
  Future<SecretKey?> getKey(String groupId) async {
    final SecretKey? cached = _cache[groupId];
    if (cached != null) {
      return cached;
    }
    try {
      final Result<Uint8List?> bytes = await store.current(groupId);
      if (bytes.isErr || bytes.value == null) {
        return null;
      }
      final SecretKey key = SecretKey(bytes.value!);
      _cache[groupId] = key;
      return key;
    } catch (_) {
      return null;
    }
  }

  /// Current key, or `Err(NotFoundFailure)` (presentation tells the user
  /// to enter the group passphrase).
  Future<Result<SecretKey>> requireKey(String groupId) async {
    final SecretKey? key = await getKey(groupId);
    if (key == null) {
      return Err(NotFoundFailure('groupkey:$groupId'));
    }
    return Ok(key);
  }

  /// True when any key is held.
  Future<bool> hasKey(String groupId) async => (await getKey(groupId)) != null;

  /// Forgets every key of [groupId].
  Future<Result<Unit>> removeKey(String groupId) async {
    _cache.remove(groupId);
    _ringCache.remove(groupId);
    return store.delete(groupId);
  }

  /// Raw key material for backups.
  Future<Result<Map<String, Uint8List>>> exportAll() => store.allCurrent();

  /// Restores backup key material.
  Future<Result<Unit>> importAll(Map<String, Uint8List> keys) async {
    for (final MapEntry<String, Uint8List> e in keys.entries) {
      final Result<Unit> saved = await store.setCurrent(e.key, e.value);
      if (saved.isErr) {
        return saved;
      }
      _cache[e.key] = SecretKey(e.value);
    }
    return const Ok(unit);
  }
}
