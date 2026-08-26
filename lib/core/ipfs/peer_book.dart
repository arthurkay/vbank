import 'dart:convert';

import '../storage/settings_dao.dart';

/// Known dialable multiaddrs of the other members of each group.
///
/// DHT provider lookups and mDNS are best effort and, in practice, two vBank
/// nodes on the same Wi-Fi never found each other through them (the DHT
/// bootstrap peers are public go-ipfs nodes the Dart stack does not fully
/// interoperate with, and multicast is often filtered). So peers also tell each
/// other where they are: the inviter's addresses ride in the invite link,
/// every signed snapshot carries its publisher's addresses, and every join
/// announcement carries the joiner's. Whatever we learn is kept here and dialed
/// on every sync round — explicit, cheap, and exactly what "put the phones on
/// the same Wi-Fi" in the guide needs to work.
class PeerBook {
  final SettingsDao _settings;
  PeerBook([SettingsDao? settings]) : _settings = settings ?? SettingsDao();

  static const _maxPerGroup = 32;
  static String _key(String groupId) => 'peers.$groupId';

  /// transport address → the peer id most recently seen behind it, across all
  /// groups. A restarted node keeps its address but gets a fresh id; entries
  /// for the old id are stale everywhere, not just in the group that told us.
  static const _transportsKey = 'peers.transports';

  Future<Map<String, String>> _transports() async {
    final raw = await _settings.get<String>(_transportsKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      return (jsonDecode(raw) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  /// Addresses for [groupId], minus any whose transport is now known to belong
  /// to a different peer id (those are dropped from the group's list as well).
  Future<List<String>> addrsFor(String groupId) async {
    final raw = await _settings.get<String>(_key(groupId));
    if (raw == null || raw.isEmpty) return const [];
    List<String> stored;
    try {
      stored = (jsonDecode(raw) as List).cast<String>();
    } catch (_) {
      return const [];
    }
    final current = await _transports();
    final live = stored.where((a) {
      final owner = current[transportOf(a)];
      return owner == null || owner == peerIdOf(a);
    }).toList();
    if (live.length != stored.length) await _settings.set(_key(groupId), jsonEncode(live));
    return live;
  }

  /// Adds [addrs] for [groupId], newest first, deduplicated and capped.
  ///
  /// A transport address (`/ip4/…/tcp/…`) has exactly one node behind it, so a
  /// new peer id at a known address replaces the old entry. dart_ipfs mints a
  /// fresh libp2p identity on every start, and dialing an address with a stale
  /// id makes the remote reject the handshake — which its router then miscounts
  /// as a disconnect from the *live* connection to that peer.
  Future<void> remember(String groupId, Iterable<String> addrs, {String? exceptPeerId}) async {
    final incoming = addrs
        .map((a) => a.trim())
        .where((a) => a.isNotEmpty && a.contains('/p2p/'))
        .where((a) => exceptPeerId == null || !a.endsWith('/p2p/$exceptPeerId'))
        .toList();
    if (incoming.isEmpty) return;
    final transports = incoming.map(transportOf).toSet();
    final current = await _transports();
    for (final a in incoming) {
      current[transportOf(a)] = peerIdOf(a);
    }
    await _settings.set(_transportsKey, jsonEncode(current));
    final existing = await addrsFor(groupId);
    final merged = <String>[
      ...incoming,
      ...existing.where((a) => !incoming.contains(a) && !transports.contains(transportOf(a))),
    ];
    await _settings.set(_key(groupId), jsonEncode(merged.take(_maxPerGroup).toList()));
  }

  /// Drops one address, e.g. after a failed dial. It comes back the next time
  /// the peer publishes anything.
  Future<void> forgetAddr(String groupId, String addr) async {
    final existing = await addrsFor(groupId);
    if (!existing.contains(addr)) return;
    await _settings.set(_key(groupId), jsonEncode(existing.where((a) => a != addr).toList()));
  }

  Future<void> forget(String groupId) => _settings.delete(_key(groupId));

  /// `/ip4/1.2.3.4/tcp/4001/p2p/Qm…` → `/ip4/1.2.3.4/tcp/4001`.
  static String transportOf(String addr) => addr.split('/p2p/').first;
  static String peerIdOf(String addr) => addr.split('/p2p/').last;
}
