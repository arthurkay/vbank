import 'dart:convert';

import '../storage/settings_dao.dart';

/// Every record CID a node has published or applied, per group.
///
/// Notifications between peers are best effort — a connection that flaps at
/// the wrong moment loses one. So on every sync round nodes also *pull*: they
/// ask each known peer for its inventory (this list) and fetch whatever they
/// have not seen. Newest first, capped; a village bank produces a few hundred
/// records a year, so the cap is years of history.
class SyncLedger {
  final SettingsDao _settings;
  SyncLedger([SettingsDao? settings]) : _settings = settings ?? SettingsDao();

  static const _max = 5000;
  static String _key(String groupId) => 'ledger.$groupId';

  Future<List<String>> cidsFor(String groupId) async {
    final raw = await _settings.get<String>(_key(groupId));
    if (raw == null || raw.isEmpty) return const [];
    try {
      return (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<bool> has(String groupId, String cid) async => (await cidsFor(groupId)).contains(cid);

  Future<void> record(String groupId, String cid) async {
    final existing = await cidsFor(groupId);
    if (existing.contains(cid)) return;
    await _settings.set(_key(groupId), jsonEncode([cid, ...existing].take(_max).toList()));
  }
}
