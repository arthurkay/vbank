import 'dart:convert';
import 'dart:typed_data';

import '../domain/repositories.dart';

/// Every record CID this node has published or applied, per group.
///
/// Notifications between peers are best effort — a flapping connection loses
/// them. So every round nodes also *pull*: they ask each known peer for its
/// inventory (this list) and fetch whatever they have not seen. Newest
/// first, capped; a village bank produces a few hundred records a year, so
/// the cap is years of history.
///
/// Persisted as JSON in settings (`ledger.<group>`), same keys as legacy.
final class SyncLedger {
  /// Application settings backing the ledger.
  final SettingsRepository settings;

  /// CIDs remembered per group.
  static const int maxPerGroup = 5000;

  /// Creates a ledger on [settings].
  SyncLedger(this.settings);

  /// Settings key for [groupId]'s CIDs.
  static String keyFor(String groupId) => 'ledger.$groupId';

  /// CIDs for [groupId], newest first. Corrupt entries read as empty.
  Future<List<String>> cidsFor(String groupId) async {
    final result = await settings.get(keyFor(groupId));
    if (result.isErr || result.value == null || result.value!.isEmpty) {
      return const [];
    }
    try {
      return (jsonDecode(utf8.decode(result.value!)) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// True when [cid] is already recorded for [groupId].
  Future<bool> has(String groupId, String cid) async =>
      (await cidsFor(groupId)).contains(cid);

  /// Records [cid] newest-first, deduplicated and capped. No-op when known.
  Future<void> record(String groupId, String cid) async {
    final List<String> existing = await cidsFor(groupId);
    if (existing.contains(cid)) {
      return;
    }
    await settings.set(
      keyFor(groupId),
      Uint8List.fromList(
        utf8.encode(jsonEncode([cid, ...existing].take(maxPerGroup).toList())),
      ),
    );
  }
}
