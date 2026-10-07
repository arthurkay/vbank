import 'dart:convert';
import 'dart:typed_data';

import '../domain/repositories.dart';

/// Remembers which records this device already published, so the
/// reconciler publishes each record once instead of every round.
///
/// Record ids (not CIDs): sealing uses a fresh nonce each time, so the
/// same record seals to a different CID on every attempt and CIDs can
/// never answer "published yet?". Duplicates stay benign regardless —
/// receivers upsert by record id — so the set is best-effort and capped.
final class PublishTracker {
  /// Opaque settings backing.
  final SettingsRepository settings;

  /// Creates the tracker.
  PublishTracker(this.settings);

  /// Ids remembered per group; oldest first. Trimmed on write.
  static const int maxIdsPerGroup = 5000;

  /// Settings key for [groupId]'s published ids.
  static String keyFor(String groupId) => 'published.$groupId';

  /// Settings key for [groupId]'s last snapshotted fingerprint.
  static String fingerprintKeyFor(String groupId) =>
      'snapshot.fingerprint.$groupId';

  /// The fingerprint stored at the last snapshot, or null when never.
  Future<String?> snapshotFingerprint(String groupId) async {
    final result = await settings.get(fingerprintKeyFor(groupId));
    if (result.isErr || result.value == null) {
      return null;
    }
    try {
      return utf8.decode(result.value!);
    } catch (_) {
      return null;
    }
  }

  /// Records the fingerprint snapshotted for [groupId].
  Future<void> recordSnapshotFingerprint(
    String groupId,
    String fingerprint,
  ) async {
    await settings.set(
      fingerprintKeyFor(groupId),
      Uint8List.fromList(utf8.encode(fingerprint)),
    );
  }

  /// True when [recordId] was published (here or applied from a peer).
  Future<bool> isPublished(String groupId, String recordId) async {
    final Set<String> ids = await _load(groupId);
    return ids.contains(recordId);
  }

  /// Remembers [recordId]. Idempotent.
  Future<void> markPublished(String groupId, String recordId) async {
    final List<String> ids = (await _load(groupId)).toList();
    if (!ids.contains(recordId)) {
      ids.add(recordId);
      while (ids.length > maxIdsPerGroup) {
        ids.removeAt(0);
      }
      await settings.set(
        keyFor(groupId),
        Uint8List.fromList(utf8.encode(jsonEncode(ids))),
      );
    }
  }

  /// Remembers every id in [recordIds].
  Future<void> markAllPublished(
    String groupId,
    Iterable<String> recordIds,
  ) async {
    final List<String> ids = (await _load(groupId)).toList();
    var dirty = false;
    for (final String id in recordIds) {
      if (!ids.contains(id)) {
        ids.add(id);
        dirty = true;
      }
    }
    if (dirty) {
      while (ids.length > maxIdsPerGroup) {
        ids.removeAt(0);
      }
      await settings.set(
        keyFor(groupId),
        Uint8List.fromList(utf8.encode(jsonEncode(ids))),
      );
    }
  }

  Future<Set<String>> _load(String groupId) async {
    final result = await settings.get(keyFor(groupId));
    if (result.isErr || result.value == null) {
      return <String>{};
    }
    try {
      return (jsonDecode(utf8.decode(result.value!)) as List)
          .cast<String>()
          .toSet();
    } catch (_) {
      return <String>{};
    }
  }
}
