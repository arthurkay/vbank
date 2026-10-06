import 'dart:convert';
import 'dart:typed_data';

import '../domain/repositories.dart';

/// Known dialable multiaddrs of the other members of each group.
///
/// DHT and mDNS discovery are best effort, so peers also tell each other
/// where they are: the inviter's addresses ride in the invite link, every
/// signed snapshot carries its publisher's addresses, and every join
/// announcement carries the joiner's. Whatever is learned is kept here and
/// dialed every round — explicit, cheap, and what "put the phones on the
/// same Wi-Fi" needs to work.
///
/// Persisted as JSON in settings (`peers.<group>`, `peers.transports`),
/// same keys as the legacy app.
final class PeerBook {
  /// Application settings backing the book.
  final SettingsRepository settings;

  /// Cap per group; invites stay scannable.
  static const int maxPerGroup = 32;

  /// Creates a book on [settings].
  PeerBook(this.settings);

  /// Transport address → peer id most recently seen behind it, across all
  /// groups. A restarted node keeps its address but gets a fresh id; entries
  /// for the old id are stale everywhere, not just in the reporting group.
  static const String transportsKey = 'peers.transports';

  /// Settings key for [groupId]'s addresses.
  static String keyFor(String groupId) => 'peers.$groupId';

  /// `/ip4/1.2.3.4/tcp/4001/p2p/Qm…` → `/ip4/1.2.3.4/tcp/4001`.
  static String transportOf(String addr) => addr.split('/p2p/').first;

  /// `/ip4/1.2.3.4/tcp/4001/p2p/Qm…` → `Qm…`.
  static String peerIdOf(String addr) => addr.split('/p2p/').last;

  /// Addresses for [groupId], minus any whose transport is now known to
  /// belong to a different peer id (also pruned from the stored list).
  ///
  /// Fails open: when the transport map itself is unreadable, staleness
  /// cannot be checked, so addresses pass through. A stale dial merely
  /// fails its handshake; dropping everything would strand the group.
  Future<List<String>> addrsFor(String groupId) async {
    final List<String> stored = await _readList(keyFor(groupId));
    if (stored.isEmpty) {
      return const [];
    }
    final Map<String, String> current = await _transports();
    final List<String> live = stored.where((String a) {
      final String? owner = current[transportOf(a)];
      return owner == null || owner == peerIdOf(a);
    }).toList();
    if (live.length != stored.length) {
      await settings.set(keyFor(groupId), _encode(live));
    }
    return live;
  }

  /// Adds [addrs] for [groupId], newest first, deduplicated and capped.
  ///
  /// One transport address has exactly one node behind it, so a new peer id
  /// at a known address replaces the old entry everywhere.
  Future<void> remember(
    String groupId,
    Iterable<String> addrs, {
    String? exceptPeerId,
  }) async {
    final List<String> incoming = addrs
        .map((String a) => a.trim())
        .where((String a) => a.isNotEmpty && a.contains('/p2p/'))
        .where(
          (String a) =>
              exceptPeerId == null || !a.endsWith('/p2p/$exceptPeerId'),
        )
        .toList();
    if (incoming.isEmpty) {
      return;
    }
    final Set<String> transports =
        incoming.map(transportOf).toSet();
    final Map<String, String> current = await _transports();
    for (final String a in incoming) {
      current[transportOf(a)] = peerIdOf(a);
    }
    await settings.set(transportsKey, _encodeMap(current));
    final List<String> existing = await addrsFor(groupId);
    final List<String> merged = [
      ...incoming,
      ...existing.where(
        (String a) =>
            !incoming.contains(a) && !transports.contains(transportOf(a)),
      ),
    ];
    await settings.set(
      keyFor(groupId),
      _encode(merged.take(maxPerGroup).toList()),
    );
  }

  /// Drops one address, e.g. after a failed dial. It returns the next time
  /// the peer publishes anything.
  Future<void> forgetAddr(String groupId, String addr) async {
    final List<String> existing = await addrsFor(groupId);
    if (!existing.contains(addr)) {
      return;
    }
    await settings.set(
      keyFor(groupId),
      _encode(existing.where((String a) => a != addr).toList()),
    );
  }

  /// Forgets a whole group, e.g. after leaving it.
  Future<void> forget(String groupId) async {
    await settings.remove(keyFor(groupId));
  }

  /// Addresses for an invite link: [own] first, then [known] members
  /// (newest first), one per transport, at most [max]. Any of them can serve
  /// the group snapshot to a joiner, so an invite survives the inviter being
  /// offline. The cap keeps the QR code scannable.
  static List<String> mergeForInvite(
    List<String> own,
    List<String> known, {
    int max = 4,
  }) {
    final List<String> out = [];
    final Set<String> transports = {};
    for (final String a in [...own, ...known]) {
      final String t = a.trim();
      if (t.isEmpty || !t.contains('/p2p/')) {
        continue;
      }
      if (!transports.add(transportOf(t))) {
        continue;
      }
      out.add(t);
      if (out.length >= max) {
        break;
      }
    }
    return out;
  }

  Future<Map<String, String>> _transports() async {
    final List<int> raw = await _readBytes(transportsKey);
    if (raw.isEmpty) {
      return {};
    }
    try {
      return (jsonDecode(utf8.decode(raw)) as Map).cast<String, String>();
    } catch (_) {
      return {};
    }
  }

  Future<List<String>> _readList(String key) async {
    final List<int> raw = await _readBytes(key);
    if (raw.isEmpty) {
      return const [];
    }
    try {
      return (jsonDecode(utf8.decode(raw)) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<List<int>> _readBytes(String key) async {
    final result = await settings.get(key);
    return result.isErr ? const [] : (result.value ?? const []);
  }

  static Uint8List _encode(List<String> addrs) =>
      Uint8List.fromList(utf8.encode(jsonEncode(addrs)));

  static Uint8List _encodeMap(Map<String, String> map) =>
      Uint8List.fromList(utf8.encode(jsonEncode(map)));
}
