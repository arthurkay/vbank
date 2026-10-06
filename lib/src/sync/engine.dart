import 'dart:convert';
import 'dart:typed_data';

import 'peer_book.dart';
import 'transport.dart';

/// Provides the group symmetric key, or null for unknown groups. Phase 5
/// implements this with the real key service; the engine only gates serving
/// and fetching on it.
typedef GroupKeyProvider = Future<Uint8List?> Function(String groupId);

/// Applies one fetched block: decrypts, verifies and stores it (phase 5).
/// [ApplyOutcome.applied] records the CID in the ledger;
/// [ApplyOutcome.rejected] parks it in the session failure set.
typedef BlockApplier = Future<ApplyOutcome> Function(
  String groupId,
  String cid,
  Uint8List block,
);

/// Outcome of applying a fetched block.
enum ApplyOutcome {
  /// Stored; fetch it no more.
  applied,

  /// Invalid (bad signature, wrong key, corrupt); do not retry this round.
  rejected,
}

/// Local block bytes by CID, for pushing to relays. Null when not held.
typedef BlockSource = Future<Uint8List?> Function(String cid);

/// Known dialable addresses per group (backed by [PeerBook] in production).
typedef PeerAddrs = Future<List<String>> Function(String groupId);

/// Ledger reads: CIDs held per group, newest first.
typedef LedgerCids = Future<List<String>> Function(String groupId);

/// Ledger writes: remembers one CID newest-first.
typedef LedgerRecord = Future<void> Function(String groupId, String cid);

/// Injectable clock. Production passes nothing ([DateTime.now]); tests pin
/// time to drive backoff deterministically.
typedef SyncClock = DateTime Function();

/// What one [SyncEngine.synchronize] round did.
final class SyncReport {
  /// Blocks fetched from peers or relays.
  final int fetched;

  /// Fetched blocks the applier accepted.
  final int applied;

  /// Blocks pushed to relays.
  final int pushed;

  /// Peers that answered inventory.
  final Set<String> contacted;

  /// Peers that stayed silent (now backing off).
  final Set<String> unreachable;

  /// Creates a round report.
  const SyncReport({
    required this.fetched,
    required this.applied,
    required this.pushed,
    required this.contacted,
    required this.unreachable,
  });

  /// An empty round: nothing moved.
  static const SyncReport empty = SyncReport(
    fetched: 0,
    applied: 0,
    pushed: 0,
    contacted: {},
    unreachable: {},
  );

  static bool _sameSets(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SyncReport &&
          fetched == other.fetched &&
          applied == other.applied &&
          pushed == other.pushed &&
          _sameSets(contacted, other.contacted) &&
          _sameSets(unreachable, other.unreachable);

  @override
  int get hashCode => Object.hash(
        fetched,
        applied,
        pushed,
        Object.hashAll(contacted.toList()..sort()),
        Object.hashAll(unreachable.toList()..sort()),
      );
}

/// The reconcile core, ported from the legacy sync manager:
///
/// local ledger ──inventory──► peers ──missing CIDs──► fetch ──apply──► store
/// local blocks ──put──► relays (for members on other networks).
///
/// Record semantics (decrypt, verify signature and role, store, conflict
/// resolution) live behind [applyBlock] in phase 5. This class only moves
/// opaque CIDs and bytes, which is why it converges without understanding
/// them. Wire shapes are identical to the legacy app, so mixed-version
/// groups and the relay interoperate.
final class SyncEngine {
  /// The P2P boundary (fake in tests).
  final SyncTransport transport;

  /// Known member addresses per group.
  final PeerAddrs peerAddrsFor;

  /// Group keys; serving and fetching require one.
  final GroupKeyProvider groupKeyFor;

  /// Ledger reads.
  final LedgerCids ledgerCids;

  /// Ledger writes.
  final LedgerRecord ledgerRecord;

  /// Record pipeline (phase 5).
  final BlockApplier applyBlock;

  /// Local blocks for relay pushes.
  final BlockSource localBlock;

  /// Clock for backoff; defaults to wall time.
  final SyncClock clock;

  /// Catches up at most this many records per peer per group per round.
  final int maxCatchUpPerRound;

  /// Pushes at most this many blocks to relays per round.
  final int maxPushPerRound;

  /// CIDs whose fetch or apply failed this session; not retried until the
  /// engine is recreated (a restart in the app).
  final Set<String> failedCids = {};

  /// Consecutive dial/request failures per peer and address.
  final Map<String, int> _peerFailures = {};
  final Map<String, DateTime> _peerBackoffUntil = {};
  final Map<String, int> _addrFailures = {};
  final Map<String, DateTime> _addrBackoffUntil = {};

  /// Creates an engine. Install [handleRequest] on the transport's
  /// `onRequest` after constructing.
  SyncEngine({
    required this.transport,
    required this.peerAddrsFor,
    required this.groupKeyFor,
    required this.ledgerCids,
    required this.ledgerRecord,
    required this.applyBlock,
    required this.localBlock,
    SyncClock? clock,
    this.maxCatchUpPerRound = 25,
    this.maxPushPerRound = 40,
  }) : clock = clock ?? DateTime.now;

  /// Answers a sync-protocol request: inventory for groups we hold a key
  /// for, empty bytes otherwise (reachable but not in the group, malformed,
  /// or anything else — callers must learn nothing from the shape).
  Future<Uint8List> handleRequest(String from, Uint8List payload) async {
    _peerReachable(from);
    Map<String, dynamic> req;
    try {
      req = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (_) {
      return Uint8List(0);
    }
    if (req['op'] != 'inventory') {
      return Uint8List(0);
    }
    final String? groupId = req['groupId'] as String?;
    if (groupId == null || await groupKeyFor(groupId) == null) {
      return Uint8List(0);
    }
    final List<String> cids = await ledgerCids(groupId);
    return Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'cids': cids})));
  }

  /// One reconcile round over [groupIds]: dials known addresses, pulls
  /// inventories, fetches and applies what is missing, and pushes local
  /// blocks the relays lack.
  Future<SyncReport> synchronize({
    required List<String> groupIds,
    required List<String> relayAddrs,
  }) async {
    int fetched = 0;
    int applied = 0;
    int pushed = 0;
    final Set<String> contacted = {};
    final Set<String> unreachable = {};
    final Set<String> relayIds =
        relayAddrs.map(PeerBook.peerIdOf).toSet();

    for (final String groupId in groupIds) {
      if (await groupKeyFor(groupId) == null) {
        continue;
      }
      final List<String> addrs = [
        ...await peerAddrsFor(groupId),
        ...relayAddrs,
      ];
      final List<String> peers = [
        ...{...addrs.map(PeerBook.peerIdOf)}..remove(transport.peerId),
      ];
      await _dialAddrs(addrs);
      final Map<String, List<String>> inventories = {};
      for (final String peer in peers) {
        final List<String>? cids = await _inventory(groupId, peer);
        if (cids == null) {
          unreachable.add(peer);
        } else {
          contacted.add(peer);
          inventories[peer] = cids;
        }
      }
      for (final MapEntry<String, List<String>> entry in inventories.entries) {
        final ({int fetched, int applied}) caughtUp =
            await _catchUp(groupId, entry.key, entry.value);
        fetched += caughtUp.fetched;
        applied += caughtUp.applied;
      }
      pushed += await _pushToRelays(groupId, inventories, relayIds);
    }
    return SyncReport(
      fetched: fetched,
      applied: applied,
      pushed: pushed,
      contacted: contacted,
      unreachable: unreachable,
    );
  }

  /// Best-effort dials; failures back the address off, successes clear it.
  /// A failed dial alone never backs the peer off — only a failed request
  /// proves unreachability.
  Future<void> _dialAddrs(List<String> addrs) async {
    final DateTime now = clock();
    for (final String addr in addrs) {
      final DateTime? until = _addrBackoffUntil[addr];
      if (until != null && now.isBefore(until)) {
        continue;
      }
      try {
        await transport.connect(addr);
        _addrFailures.remove(addr);
        _addrBackoffUntil.remove(addr);
      } catch (_) {
        final int failures = ((_addrFailures[addr] ?? 0) + 1).clamp(1, 6);
        _addrFailures[addr] = failures;
        _addrBackoffUntil[addr] = now.add(_backoffFor(failures));
      }
    }
  }

  /// Asks [peer] what it holds for [groupId]. Null when silent (backed off)
  /// or incomprehensible; empty list when reachable but not in the group.
  Future<List<String>?> _inventory(String groupId, String peer) async {
    final DateTime now = clock();
    final DateTime? until = _peerBackoffUntil[peer];
    if (until != null && now.isBefore(until)) {
      return null;
    }
    final Uint8List request = Uint8List.fromList(
      utf8.encode(jsonEncode({'op': 'inventory', 'groupId': groupId})),
    );
    final Uint8List? reply = await transport.request(peer, request);
    if (reply == null) {
      _peerFailed(peer, now);
      return null;
    }
    _peerReachable(peer);
    if (reply.isEmpty) {
      return const [];
    }
    try {
      return ((jsonDecode(utf8.decode(reply)) as Map)['cids'] as List)
          .cast<String>();
    } catch (_) {
      return null;
    }
  }

  /// Fetches CIDs in [theirs] that are missing locally, oldest first (their
  /// list is newest first; snapshots must land before the records that
  /// depend on them). Returns how many were fetched and applied.
  Future<({int fetched, int applied})> _catchUp(
    String groupId,
    String peer,
    List<String> theirs,
  ) async {
    final Set<String> mine = (await ledgerCids(groupId)).toSet();
    final Iterable<String> missing = theirs.reversed
        .where((String c) => !mine.contains(c) && !failedCids.contains(c))
        .take(maxCatchUpPerRound);
    var fetched = 0;
    var applied = 0;
    for (final String cid in missing) {
      final Uint8List? bytes = await transport.fetchBlock(cid, [peer]);
      if (bytes == null) {
        failedCids.add(cid);
        continue;
      }
      fetched++;
      final ApplyOutcome outcome = await applyBlock(groupId, cid, bytes);
      if (outcome == ApplyOutcome.applied) {
        await ledgerRecord(groupId, cid);
        mine.add(cid);
        applied++;
      } else {
        failedCids.add(cid);
      }
    }
    return (fetched: fetched, applied: applied);
  }

  /// Pushes local blocks the relays lack (members pull for themselves).
  /// Reuses the inventories already fetched this round.
  Future<int> _pushToRelays(
    String groupId,
    Map<String, List<String>> inventories,
    Set<String> relayIds,
  ) async {
    final Set<String> mine = (await ledgerCids(groupId)).toSet();
    var pushed = 0;
    for (final MapEntry<String, List<String>> entry in inventories.entries) {
      if (!relayIds.contains(entry.key)) {
        continue;
      }
      final Set<String> theirs = entry.value.toSet();
      for (final String cid in mine.toList().reversed) {
        if (theirs.contains(cid) || pushed >= maxPushPerRound) {
          continue;
        }
        final Uint8List? bytes = await localBlock(cid);
        if (bytes == null) {
          continue;
        }
        if (await _put(entry.key, groupId, cid, bytes)) {
          pushed++;
        }
      }
    }
    return pushed;
  }

  /// Hands one block to a relay. False covers every failure mode; the peer
  /// backoff already advanced when the inventory reply went missing, and a
  /// refused put is retried next round like any other missing block.
  Future<bool> _put(
    String peer,
    String groupId,
    String cid,
    Uint8List block,
  ) async {
    final Uint8List payload = Uint8List.fromList(
      utf8.encode(
        jsonEncode({
          'op': 'put',
          'groupId': groupId,
          'cid': cid,
          'block': base64Encode(block),
        }),
      ),
    );
    final Uint8List? reply = await transport.request(peer, payload);
    if (reply == null || reply.isEmpty) {
      return false;
    }
    try {
      return (jsonDecode(utf8.decode(reply)) as Map)['stored'] == true;
    } catch (_) {
      return false;
    }
  }

  /// PubSub topic for a group. The id is random, so the name reveals
  /// nothing about the group.
  static String topicFor(String groupId) => 'vbank/group/$groupId';

  bool _peerInBackoff(String peer) {
    final DateTime? until = _peerBackoffUntil[peer];
    return until != null && clock().isBefore(until);
  }

  void _peerFailed(String peer, DateTime now) {
    final int failures = ((_peerFailures[peer] ?? 0) + 1).clamp(1, 6);
    _peerFailures[peer] = failures;
    _peerBackoffUntil[peer] = now.add(_backoffFor(failures));
  }

  /// Anything heard from a peer proves reachability: forget every backoff
  /// so the next push goes straight out.
  void _peerReachable(String peer) {
    _peerFailures.remove(peer);
    _peerBackoffUntil.remove(peer);
    _addrBackoffUntil.removeWhere(
      (String addr, _) => addr.endsWith('/p2p/$peer'),
    );
    _addrFailures.removeWhere(
      (String addr, _) => addr.endsWith('/p2p/$peer'),
    );
  }

  /// 15 s, 30 s, 60 s … capped at 300 s, matching the legacy manager.
  static Duration _backoffFor(int failures) =>
      Duration(seconds: (15 << (failures - 1)).clamp(15, 300));

  /// True while [peer] is backing off. Exposed for tests.
  bool peerInBackoff(String peer) => _peerInBackoff(peer);
}
