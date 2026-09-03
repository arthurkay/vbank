import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:cryptography/cryptography.dart';
import 'package:dart_ipfs/dart_ipfs.dart' show PubSubMessage;

import '../../models/group.dart';
import '../../models/loan.dart';
import '../../models/meeting.dart';
import '../../models/transaction.dart';
import '../../models/transaction_reversal.dart';
import '../../services/governance_service.dart';
import '../../services/group_key_service.dart';
import '../../services/group_service.dart';
import '../../services/invite_service.dart';
import '../../services/loan_service.dart';
import '../../services/meeting_service.dart';
import '../../services/transaction_service.dart';
import '../crypto/signing.dart';
import '../crypto/sync_envelope.dart';
import '../storage/invite_dao.dart';
import '../storage/settings_dao.dart';
import 'ipfs_service.dart';
import 'peer_book.dart';
import 'pending_join.dart';
import '../crypto/invite_wrap.dart';
import '../relay/relay_directory.dart';
import 'sync_ledger.dart';

enum SyncState { idle, syncing, error }

/// Thrown by [SyncManager.joinGroup] when the invite cannot be honoured.
class JoinGroupException implements Exception {
  final String message;
  const JoinGroupException(this.message);
  @override
  String toString() => message;
}

/// Nobody holding the group was reachable; the join has been parked and will
/// be retried at the end of every sync round (see [PendingJoin]).
class JoinParkedException extends JoinGroupException {
  const JoinParkedException()
      : super('Nobody from the group is online right now. vBank will keep trying in the '
            'background and tell you when you are in.');
}

/// Something that arrived from a peer and changed local state. The UI layer
/// listens to refresh screens and raise local notifications.
class SyncChange {
  final SyncChangeType type;
  final String groupId;
  final String? title;
  final String? body;

  /// Id of the record that changed (transaction, loan, meeting, reversal id;
  /// the member's peer id for joins) so a tapped notification can open it.
  final String? recordId;
  const SyncChange(this.type, this.groupId, {this.title, this.body, this.recordId});
}

enum SyncChangeType { transaction, group, member, loan, meeting, reversal }

/// Coordinates everything that crosses the IPFS boundary (DESIGN_PLAN §9):
///
///   local signed data ──encrypt(group key)──► IPFS CID ──PubSub──► peers
///   peers ──PubSub CID──► fetch ──decrypt(group key)──► verify sig+role ──► store
///
/// Nothing leaves this class unencrypted except PubSub notifications, which
/// carry only a CID and the (random UUID) group id.
class SyncManager {
  final IpfsService _ipfsService;
  final TransactionService _transactionService;
  final GroupService _groupService;
  final GroupKeyService _groupKeyService;
  final LoanService _loanService;
  final MeetingService _meetingService;
  final GovernanceService _governanceService;
  final InviteService _inviteService;
  final PeerBook _peerBook = PeerBook();
  final SyncLedger _ledger = SyncLedger();
  final PendingJoinBook _pendingJoins = PendingJoinBook();
  final SettingsDao _settings = SettingsDao();

  /// Always-on relay nodes (multiaddrs). Phones sit behind carrier NAT and can
  /// only reach each other through a node that accepts connections, so every
  /// device dials the relays out, pushes its records to them and pulls what it
  /// lacks from them. The relays hold no group key. Loaded lazily.
  List<String>? _relayAddrs;
  static const _maxRelayPushPerRound = 40;

  /// The relay vBank ships with (see kBuiltInRelayHosts): its peer id is
  /// discovered from a `_dnsaddr` TXT record, cached, and the last good answer
  /// persisted so an offline start still knows the address.
  final RelayDirectory _relayDirectory = RelayDirectory();
  bool? _builtInRelayEnabled;
  List<String>? _builtInRelayAddrs;
  DateTime? _builtInRelayNextLookup;

  /// Groups with a join in flight (interactive or retried), so the two paths
  /// cannot both import the snapshot and publish a join request.
  final _joiningGroups = <String>{};

  /// CIDs whose fetch/apply failed this session; not retried until restart.
  final _failedCids = <String>{};

  /// Per-address dial backoff (see [_dialKnownPeers]).
  final _dialFailures = <String, int>{};
  final _dialBackoffUntil = <String, DateTime>{};

  /// Peers that did not answer recently. A treasurer's device knows every
  /// member of every group it has ever been in; members who changed phones or
  /// are simply offline must not cost a dial timeout per group per round, or
  /// pushes for the live groups queue behind them for minutes.
  final _peerFailures = <String, int>{};
  final _peerBackoffUntil = <String, DateTime>{};

  /// A publish asked for while a round was busy; the round runs once more.
  bool _rerunRequested = false;
  Future<void> _publishChain = Future.value();

  bool _peerInBackoff(String peerId) {
    final until = _peerBackoffUntil[peerId];
    return until != null && DateTime.now().isBefore(until);
  }

  void _peerFailed(String peerId) {
    final failures = (_peerFailures[peerId] = (_peerFailures[peerId] ?? 0) + 1);
    _peerBackoffUntil[peerId] = DateTime.now().add(Duration(seconds: (15 << (failures - 1)).clamp(15, 300)));
  }

  /// Anything heard from a peer proves it is reachable: forget the backoff so
  /// the next push goes straight out.
  void _peerReachable(String peerId) {
    _peerFailures.remove(peerId);
    _peerBackoffUntil.remove(peerId);
    _dialBackoffUntil.removeWhere((addr, _) => addr.endsWith('/p2p/$peerId'));
    _dialFailures.removeWhere((addr, _) => addr.endsWith('/p2p/$peerId'));
  }

  /// CIDs already handled from notifications (insertion-ordered, capped).
  final _seenNotifications = <String>{};

  SyncState _state = SyncState.idle;
  DateTime? _lastSyncTime;
  Duration _syncInterval = const Duration(minutes: 2);
  Timer? _periodicSyncTimer;
  Timer? _backgroundStopTimer;

  final _stateController = StreamController<SyncState>.broadcast();
  final _syncLogController = StreamController<SyncEvent>.broadcast();
  final _changesController = StreamController<SyncChange>.broadcast();
  final List<SyncEvent> _recentLog = [];
  static const _maxLog = 200;

  StreamSubscription<PubSubMessage>? _pubsubSub;
  final Set<String> _subscribedGroups = {};

  /// Who we are; set by the auth layer.
  String? _ownPeerId;
  SimpleKeyPair? _ownKeyPair;

  SyncState get state => _state;
  DateTime? get lastSyncTime => _lastSyncTime;
  Stream<SyncState> get stateStream => _stateController.stream;
  Stream<SyncEvent> get syncLogStream => _syncLogController.stream;
  Stream<SyncChange> get changes => _changesController.stream;
  List<SyncEvent> get recentLog => List.unmodifiable(_recentLog);

  SyncManager({
    required IpfsService ipfsService,
    required TransactionService transactionService,
    required GroupService groupService,
    required GroupKeyService groupKeyService,
    required LoanService loanService,
    required MeetingService meetingService,
    required GovernanceService governanceService,
    required InviteService inviteService,
  })  : _ipfsService = ipfsService,
        _transactionService = transactionService,
        _groupService = groupService,
        _groupKeyService = groupKeyService,
        _loanService = loanService,
        _meetingService = meetingService,
        _governanceService = governanceService,
        _inviteService = inviteService;

  /// PubSub topic for a group. The id is a random UUID, so the topic name
  /// itself reveals nothing about the group.
  static String topicFor(String groupId) => 'vbank/group/$groupId';

  void setIdentity({String? peerId, SimpleKeyPair? keyPair}) {
    _ownPeerId = peerId;
    _ownKeyPair = keyPair;
  }

  // ---------------------------------------------------------------------------
  // Lifecycle (DESIGN_PLAN §10)
  // ---------------------------------------------------------------------------

  String? _lastError;
  String? get lastError => _lastError;
  bool _backgroundStarted = false;

  /// App-launch / resume entry point: brings the IPFS node up (best effort),
  /// schedules periodic syncs and runs one now. Idempotent.
  Future<void> startBackground({Duration? interval}) async {
    _backgroundStopTimer?.cancel();
    _backgroundStopTimer = null;
    if (!_backgroundStarted || _periodicSyncTimer == null) {
      _backgroundStarted = true;
      startPeriodicSync(interval: interval);
    }
    await startManualSync();
  }

  /// App went to the background: stop periodic syncs now and shut the node
  /// down after 15 minutes so it doesn't drain the battery (§10). Resuming
  /// via [startBackground] cancels the shutdown.
  void pauseBackground({Duration stopAfter = const Duration(minutes: 15)}) {
    stopPeriodicSync();
    _backgroundStopTimer?.cancel();
    _backgroundStopTimer = Timer(stopAfter, () async {
      if (_state == SyncState.syncing) return;
      await stopNode();
    });
  }

  Future<void> stopNode() async {
    await _pubsubSub?.cancel();
    _pubsubSub = null;
    _subscribedGroups.clear();
    try {
      await _ipfsService.stop();
      _log(SyncEvent(type: SyncEventType.nodeStopped, message: 'IPFS node stopped'));
    } catch (e) {
      _log(SyncEvent(type: SyncEventType.error, message: 'Failed to stop node: $e'));
    }
  }

  Future<void> startManualSync({Duration? duration}) async {
    if (_state == SyncState.syncing) {
      // A round is already walking the groups (possibly waiting on dead
      // peers). Push local changes right now regardless, and run one more
      // round when this one finishes so nothing is left behind.
      _rerunRequested = true;
      await publishLocalChanges();
      return;
    }
    final syncDuration = duration ?? const Duration(seconds: 60);

    _setState(SyncState.syncing);
    _log(SyncEvent(type: SyncEventType.started, message: 'Sync started'));

    try {
      await _runSync().timeout(syncDuration);
      _lastSyncTime = DateTime.now().toUtc();
      _lastError = null;
      _log(SyncEvent(type: SyncEventType.completed, message: 'Sync completed'));
      _setState(SyncState.idle);
    } on TimeoutException {
      _lastError = 'Sync timed out after ${syncDuration.inSeconds}s';
      _setState(SyncState.error);
      _log(SyncEvent(type: SyncEventType.error, message: _lastError!));
    } catch (e) {
      _lastError = 'Sync failed: $e';
      _setState(SyncState.error);
      _log(SyncEvent(type: SyncEventType.error, message: _lastError!));
    }
    // Outside the round budget: a parked join dials addresses nobody has
    // answered from, and must not starve the groups we are already in.
    await retryPendingJoinsNow();
  }

  Future<void> _runSync() async {
    await _ensureNode();
    await _subscribeGroupTopics();
    await _refreshOverdueLoans();
    await _dialRelays();
    await publishLocalChanges();
    await _reconcileRelays();
    await _discoverPeers();
    if (_rerunRequested) {
      _rerunRequested = false;
      await publishLocalChanges();
      await _discoverPeers();
    }
  }

  /// Publishes snapshots and transactions that are not on the network yet.
  /// Serialised so two callers cannot publish the same record twice; safe to
  /// call at any time, including while a round is in progress.
  Future<void> publishLocalChanges() {
    final next = _publishChain.then((_) async {
      await _ensureNode();
      await _publishMissingSnapshots();
      await _syncPendingTransactions();
    });
    _publishChain = next.catchError((_) {});
    return next;
  }

  /// Where other members can dial this node (empty until the node is up).
  List<String> get dialableAddresses => _ipfsService.dialableAddresses;

  /// Addresses for an invite link: ours plus every member of [groupId] we know
  /// how to reach, so the invite still works while we are offline — any of
  /// them holds the snapshot the joiner needs.
  Future<List<String>> inviteAddresses(String groupId) async =>
      PeerBook.mergeForInvite(dialableAddresses, await _peerBook.addrsFor(groupId));

  // ---------------------------------------------------------------------------
  // Relays
  // ---------------------------------------------------------------------------

  /// Relays the user added (also what invite links carry).
  Future<List<String>> userRelayAddresses() async {
    if (_relayAddrs != null) return _relayAddrs!;
    final raw = await _settings.get<String>(SettingKeys.relayAddrs);
    List<String> list = const [];
    if (raw != null && raw.isNotEmpty) {
      try {
        list = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {}
    }
    return _relayAddrs = list;
  }

  Future<bool> builtInRelayEnabled() async =>
      _builtInRelayEnabled ??= await _settings.getBool(SettingKeys.builtInRelayEnabled, defaultValue: true);

  Future<void> setBuiltInRelayEnabled(bool enabled) async {
    _builtInRelayEnabled = enabled;
    if (enabled) _builtInRelayNextLookup = null;
    await _settings.set(SettingKeys.builtInRelayEnabled, enabled);
    _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'vBank relay ${enabled ? 'enabled' : 'disabled'}'));
  }

  /// Addresses of the built-in relay: resolved via DNS at most hourly, else the
  /// last persisted answer. Empty when disabled or never resolved.
  Future<List<String>> builtInRelayAddresses() async {
    if (!await builtInRelayEnabled()) return const [];
    // One DNS lookup per hour when it works, one per five minutes while it
    // does not; in between, the last known answer (memory, then settings).
    final next = _builtInRelayNextLookup;
    if (next == null || !DateTime.now().isBefore(next)) {
      final fresh = <String>[];
      for (final host in kBuiltInRelayHosts) {
        fresh.addAll(await _relayDirectory.resolve(host));
      }
      if (fresh.isNotEmpty) {
        _builtInRelayAddrs = fresh;
        _builtInRelayNextLookup = DateTime.now().add(const Duration(hours: 1));
        await _settings.set(SettingKeys.builtInRelayCache, jsonEncode(fresh));
        return fresh;
      }
      _builtInRelayNextLookup = DateTime.now().add(const Duration(minutes: 5));
      _log(SyncEvent(
        type: SyncEventType.warning,
        message: 'vBank relay (${kBuiltInRelayHosts.join(', ')}) not resolvable right now — retrying in 5 min',
      ));
    }
    final cached = _builtInRelayAddrs;
    if (cached != null) return cached;
    final raw = await _settings.get<String>(SettingKeys.builtInRelayCache);
    if (raw != null && raw.isNotEmpty) {
      try {
        return _builtInRelayAddrs = (jsonDecode(raw) as List).cast<String>();
      } catch (_) {}
    }
    return const [];
  }

  /// Every relay in use: the user's plus the built-in one.
  Future<List<String>> relayAddresses() async {
    final user = await userRelayAddresses();
    final builtIn = await builtInRelayAddresses();
    return {...user, ...builtIn}.toList();
  }

  Future<Set<String>> _relayPeerIds() async =>
      (await relayAddresses()).map(PeerBook.peerIdOf).toSet()..remove(_ownPeerId);

  /// Adds relays (e.g. from an invite link); returns whether anything changed.
  Future<bool> addRelays(Iterable<String> addrs) async {
    final current = await userRelayAddresses();
    final clean = addrs.map((a) => a.trim()).where((a) => a.contains('/p2p/') && !current.contains(a)).toList();
    if (clean.isEmpty) return false;
    await _saveRelays([...current, ...clean]);
    _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Relay added: ${clean.join(', ')}'));
    return true;
  }

  Future<void> removeRelay(String addr) async {
    final current = await userRelayAddresses();
    if (!current.contains(addr)) return;
    await _saveRelays(current.where((a) => a != addr).toList());
  }

  Future<void> _saveRelays(List<String> addrs) async {
    _relayAddrs = addrs;
    if (addrs.isEmpty) {
      await _settings.delete(SettingKeys.relayAddrs);
    } else {
      await _settings.set(SettingKeys.relayAddrs, jsonEncode(addrs));
    }
  }

  /// Dials every relay (per-address backoff applies) and returns the relay
  /// peer ids that are connected afterwards.
  Future<Set<String>> _dialRelays() async {
    final addrs = await relayAddresses();
    if (addrs.isEmpty) return const {};
    final connected = (await _ipfsService.connectedPeers).toSet();
    for (final addr in addrs) {
      final peerId = PeerBook.peerIdOf(addr);
      if (connected.contains(peerId)) continue;
      final until = _dialBackoffUntil[addr];
      if (until != null && DateTime.now().isBefore(until)) continue;
      try {
        await _ipfsService.connectToPeer(addr).timeout(const Duration(seconds: 8));
        _dialFailures.remove(addr);
        _dialBackoffUntil.remove(addr);
        _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Connected to relay $addr'));
      } catch (e) {
        final failures = (_dialFailures[addr] = (_dialFailures[addr] ?? 0) + 1);
        final backoff = Duration(seconds: (15 << (failures - 1)).clamp(15, 300));
        _dialBackoffUntil[addr] = DateTime.now().add(backoff);
        _log(SyncEvent(type: SyncEventType.warning, message: 'Relay unreachable $addr (retry in ${backoff.inSeconds}s)'));
      }
    }
    final relays = await _relayPeerIds();
    return (await _ipfsService.connectedPeers).toSet().intersection(relays);
  }

  /// Hands a stored block to every connected relay (`put`), so members on other
  /// networks can fetch it from there. Best effort; [_reconcileRelays] catches
  /// up on anything missed.
  Future<void> _pushToRelays(String groupId, String cid, {Uint8List? bytes}) async {
    final relays = (await _ipfsService.connectedPeers).toSet().intersection(await _relayPeerIds());
    if (relays.isEmpty) return;
    final block = bytes ?? await _ipfsService.getDataLocal(cid);
    if (block == null) return;
    final payload = Uint8List.fromList(utf8.encode(jsonEncode({
      'op': 'put',
      'groupId': groupId,
      'cid': cid,
      'block': base64Encode(block),
      'addrs': dialableAddresses,
    })));
    for (final relay in relays) {
      final reply = await _ipfsService.request(relay, payload);
      if (reply == null) _log(SyncEvent(type: SyncEventType.warning, message: 'Relay $relay did not take $cid'));
    }
  }

  /// Makes sure each connected relay holds everything in our ledger for every
  /// group we hold a key for (bounded per round).
  Future<void> _reconcileRelays() async {
    final relays = await _dialRelays();
    if (relays.isEmpty) return;
    var pushed = 0;
    for (final g in await _groupService.getAllGroups()) {
      if (!await _groupKeyService.hasKey(g.id)) continue;
      final mine = await _ledger.cidsFor(g.id);
      if (mine.isEmpty) continue;
      final request = Uint8List.fromList(utf8.encode(jsonEncode({'op': 'inventory', 'groupId': g.id})));
      for (final relay in relays) {
        final reply = await _ipfsService.request(relay, request);
        if (reply == null) continue;
        Set<String> theirs;
        try {
          theirs = reply.isEmpty ? {} : ((jsonDecode(utf8.decode(reply)) as Map)['cids'] as List).cast<String>().toSet();
        } catch (_) {
          continue;
        }
        for (final cid in mine.reversed) {
          if (theirs.contains(cid) || pushed >= _maxRelayPushPerRound) continue;
          await _pushToRelays(g.id, cid);
          pushed++;
        }
      }
    }
    if (pushed > 0) _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Pushed $pushed record(s) to relays'));
  }

  /// Dials every address we know for [groupId]'s members. Failures are
  /// expected (phones move, addresses go stale) and ignored.
  ///
  /// With [force] peers the router already lists as connected are dialed too:
  /// libp2p's connect is a no-op on a live connection and a reconnect on one
  /// that died without the router noticing — which is what a failed fetch from
  /// a supposedly connected peer usually means.
  Future<void> _dialKnownPeers(String groupId, {bool force = true}) async {
    // Always dial, even peers the router lists as connected: libp2p's connect
    // is a no-op on a live connection, a reconnect on a dead one, and — the
    // part that matters — it re-registers the address in the peer store,
    // whose entries expire after ten minutes ("No addresses found for peer").
    final connected = force ? <String>{} : (await _ipfsService.connectedPeers).toSet();
    for (final addr in await _peerBook.addrsFor(groupId)) {
      final peerId = addr.split('/p2p/').last;
      if (peerId == _ipfsService.peerId) continue;
      if (connected.contains(peerId)) continue;
      if (_peerInBackoff(peerId)) continue;
      final until = _dialBackoffUntil[addr];
      if (until != null && DateTime.now().isBefore(until)) continue;
      try {
        await _ipfsService.connectToPeer(addr).timeout(const Duration(seconds: 8));
        // A "successful" connect is not proof of life — dart_ipfs reports
        // success for addresses it merely re-registered — so only the address
        // backoff is cleared here; the peer backoff waits for a real reply.
        _dialFailures.remove(addr);
        _dialBackoffUntil.remove(addr);
        connected.add(peerId);
        _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Connected to $addr'));
      } catch (e) {
        // Unreachable right now (asleep, restarting, Wi-Fi hiccup, moved
        // network). Peer ids are stable, so the address is either still right
        // or will be replaced by the peer's next announcement — never drop it,
        // just back off so a dead address does not cost 8 s every round.
        final failures = (_dialFailures[addr] = (_dialFailures[addr] ?? 0) + 1);
        final backoff = Duration(seconds: (15 << (failures - 1)).clamp(15, 300));
        _dialBackoffUntil[addr] = DateTime.now().add(backoff);
        _log(SyncEvent(type: SyncEventType.warning, message: 'Dial failed $addr (retry in ${backoff.inSeconds}s): $e'));
      }
    }
  }

  // ---------------------------------------------------------------------------
  // Pull-based catch-up (see SyncLedger)
  // ---------------------------------------------------------------------------

  static const _maxCatchUpPerRound = 25;

  /// Answers `/vbank/sync` requests: currently only `inventory`, which lists
  /// the record CIDs we hold for a group we are in. CIDs are opaque and every
  /// record is encrypted with the group key, so this reveals nothing to a
  /// stranger beyond "there is a group with this id".
  Future<Uint8List> _onSyncRequest(String from, Uint8List payload) async {
    _peerReachable(from);
    _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Sync request from $from (${payload.length} bytes)'));
    Map<String, dynamic> req;
    try {
      req = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (_) {
      return Uint8List(0);
    }
    if (req['op'] != 'inventory') return Uint8List(0);
    final groupId = req['groupId'] as String?;
    if (groupId == null || await _groupKeyService.getKey(groupId) == null) return Uint8List(0);
    final cids = await _ledger.cidsFor(groupId);
    _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Served inventory (${cids.length}) to $from'));
    return Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'cids': cids})));
  }

  /// Asks every known peer of [groupId] what it holds and fetches what we lack.
  /// Notifications are best effort; this is what makes sync converge.
  Future<void> _pullInventory(String groupId) async {
    final peers = {
      ...(await _peerBook.addrsFor(groupId)).map(PeerBook.peerIdOf),
      ...await _relayPeerIds(),
    }..remove(_ipfsService.peerId);
    if (peers.isEmpty) return;
    final request = Uint8List.fromList(utf8.encode(jsonEncode({'op': 'inventory', 'groupId': groupId})));
    var applied = 0;
    for (final peer in peers) {
      if (_peerInBackoff(peer)) continue;
      final reply = await _ipfsService.request(peer, request);
      if (reply == null) {
        // Unreachable (dial failure or timeout): back off, do not ask again
        // for every group this round.
        _peerFailed(peer);
        final wait = _peerBackoffUntil[peer]!.difference(DateTime.now()).inSeconds;
        _log(SyncEvent(type: SyncEventType.warning, message: 'No inventory from $peer for $groupId (retry in ${wait}s)'));
        continue;
      }
      _peerReachable(peer);
      if (reply.isEmpty) {
        // Reachable but not (or no longer) in this group.
        continue;
      }
      List<String> theirs;
      try {
        theirs = ((jsonDecode(utf8.decode(reply)) as Map)['cids'] as List).cast<String>();
      } catch (_) {
        continue;
      }
      final mine = (await _ledger.cidsFor(groupId)).toSet();
      // Their list is newest first; apply oldest first so snapshots and the
      // records that depend on them arrive in order.
      final missing = theirs.reversed.where((c) => !mine.contains(c) && !_failedCids.contains(c)).take(_maxCatchUpPerRound);
      for (final cid in missing) {
        try {
          await _fetchAndApply(groupId, cid, from: peer);
          applied++;
        } catch (e) {
          _failedCids.add(cid);
          _log(SyncEvent(type: SyncEventType.error, message: 'Catch-up rejected $cid: $e'));
        }
      }
    }
    if (applied > 0) {
      _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Caught up $applied record(s) for $groupId'));
    }
  }

  /// Waits briefly (the libp2p notifiee can lag the dial) until any of
  /// [peerIds] shows up as connected, and returns the connected subset.
  Future<Set<String>> _awaitAnyConnected(Set<String> peerIds, {Duration timeout = const Duration(seconds: 3)}) async {
    if (peerIds.isEmpty) return const {};
    final deadline = DateTime.now().add(timeout);
    while (true) {
      final up = (await _ipfsService.connectedPeers).toSet().intersection(peerIds);
      if (up.isNotEmpty || !DateTime.now().isBefore(deadline)) return up;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
  }

  Future<void> _ensureNode() async {
    _ipfsService.requestHandler ??= _onSyncRequest;
    if (!_ipfsService.isRunning) {
      await _ipfsService.start();
      _log(SyncEvent(type: SyncEventType.nodeStarted, message: 'IPFS node started as ${_ipfsService.peerId}'));
      await _pubsubSub?.cancel();
      _pubsubSub = null;
      _subscribedGroups.clear();
    }
    _pubsubSub ??= _ipfsService.pubsubMessages.listen(
      _onPubSubMessage,
      onError: (Object e) =>
          _log(SyncEvent(type: SyncEventType.error, message: 'PubSub stream error: $e')),
    );
  }

  Future<void> stopSync() async {
    if (_state != SyncState.syncing) return;
    _setState(SyncState.idle);
    _log(SyncEvent(type: SyncEventType.stopped, message: 'Sync stopped'));
  }

  void startPeriodicSync({Duration? interval}) {
    _syncInterval = interval ?? _syncInterval;
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = Timer.periodic(_syncInterval, (_) async {
      if (_state != SyncState.syncing) await startManualSync();
    });
  }

  void stopPeriodicSync() {
    _periodicSyncTimer?.cancel();
    _periodicSyncTimer = null;
  }

  Future<void> _refreshOverdueLoans() async {
    for (final g in await _groupService.getAllGroups()) {
      try {
        await _loanService.refreshOverdue(g.id);
      } catch (e) {
        _log(SyncEvent(type: SyncEventType.error, message: 'Overdue check failed for ${g.name}: $e'));
      }
    }
  }

  /// Dials each group's known members and pulls what we lack from them.
  ///
  /// There is no DHT lookup here: vBank runs without bootstrap peers, so
  /// `findProviders` could only ever time out (10 s per group per round —
  /// with a dozen groups that alone blew the round budget).
  Future<void> _discoverPeers() async {
    for (final g in await _groupService.getAllGroups()) {
      await _dialKnownPeers(g.id);
      await _pullInventory(g.id);
    }
  }

  // ---------------------------------------------------------------------------
  // Outbound
  // ---------------------------------------------------------------------------

  Future<void> _subscribeGroupTopics() async {
    for (final g in await _groupService.getAllGroups()) {
      if (_subscribedGroups.contains(g.id)) continue;
      if (!await _groupKeyService.hasKey(g.id)) continue;
      await _ipfsService.subscribe(topicFor(g.id));
      _subscribedGroups.add(g.id);
    }
  }

  Future<void> _publishMissingSnapshots() async {
    for (final g in await _groupService.getAllGroups()) {
      if (g.cid != null) continue;
      if (!await _groupKeyService.hasKey(g.id)) continue;
      if (!await _canPublish(g)) continue;
      try {
        await publishGroupSnapshot(g.id);
      } catch (e) {
        _log(SyncEvent(type: SyncEventType.error, message: 'Failed to publish snapshot for ${g.name}: $e'));
      }
    }
  }

  Future<bool> _canPublish(Group g) async {
    final me = _ownPeerId;
    if (me == null || _ownKeyPair == null) return false;
    final m = g.members.where((m) => m.peerId == me).firstOrNull;
    return m != null && m.status == MemberStatus.active && _groupService.canWrite(m.role);
  }

  /// Signs, encrypts and publishes the group's metadata; records the CID and
  /// notifies members. Only owners/admins may publish (enforced in
  /// GroupService.buildSnapshot).
  Future<String> publishGroupSnapshot(String groupId) async {
    final me = _ownPeerId;
    final kp = _ownKeyPair;
    if (me == null || kp == null) throw StateError('Not signed in');
    await _ensureNode();
    final key = await _groupKeyService.requireKey(groupId);
    final snapshot = await _groupService.buildSnapshot(
      groupId,
      publisherPeerId: me,
      publisherKeyPair: kp,
      publisherAddrs: dialableAddresses,
    );

    // One wrapped copy of the group key per live invite rides in the clear, so
    // a joiner holding an invite secret can open the snapshot. Used or expired
    // invites drop out here — their links stop working.
    final wraps = <String, Uint8List>{
      for (final i in await _inviteService.liveInvites(groupId))
        if (i.wrappedKey != null) i.id: i.wrappedKey!,
    };
    final bytes = await SyncEnvelope.seal(
      type: SyncPayloadType.groupSnapshot,
      groupId: groupId,
      plaintextJson: snapshot,
      groupKey: key,
      wraps: wraps,
    );
    final cid = await _ipfsService.addData(bytes);
    await _ipfsService.pin(cid);
    await _groupService.setCid(groupId, cid);
    await _ledger.record(groupId, cid);
    await _announce(groupId, 'group', cid);
    _log(SyncEvent(type: SyncEventType.snapshotPublished, message: 'Group snapshot → $cid'));
    return cid;
  }

  /// Generic: seal a signed record and publish it to the group's topic.
  Future<String> publishRecord(String groupId, SyncPayloadType type, Map<String, dynamic> json) async {
    await _ensureNode();
    final key = await _groupKeyService.requireKey(groupId);
    final bytes = await SyncEnvelope.seal(type: type, groupId: groupId, plaintextJson: json, groupKey: key);
    final String cid;
    try {
      cid = await _ipfsService.addData(bytes);
      await _ipfsService.pin(cid);
      await _ledger.record(groupId, cid);
    } catch (e) {
      _log(SyncEvent(type: SyncEventType.error, message: 'Storing ${type.name} failed: $e'));
      rethrow;
    }
    try {
      await _announce(groupId, type.name, cid);
    } catch (e) {
      // The record is stored and pinned; peers still pick it up on their next
      // sync round, so a failed nudge must not fail the caller's operation.
      _log(SyncEvent(type: SyncEventType.error, message: 'Announcing ${type.name} $cid failed: $e'));
    }
    return cid;
  }

  Future<void> publishLoan(LoanRequest loan) => publishRecord(loan.groupId, SyncPayloadType.loan, loan.toJson());
  Future<void> publishMeeting(Meeting m) => publishRecord(m.groupId, SyncPayloadType.meeting, m.toJson());
  Future<void> publishReversal(TransactionReversal r) =>
      publishRecord(r.groupId, SyncPayloadType.reversal, r.toJson());

  Future<void> _syncPendingTransactions() async {
    final unsynced = await _transactionService.getUnsynced();
    if (unsynced.isNotEmpty) {
      _log(SyncEvent(type: SyncEventType.syncStarted, message: 'Syncing ${unsynced.length} pending transactions'));
    }
    for (final tx in unsynced) {
      try {
        final key = await _groupKeyService.getKey(tx.groupId);
        if (key == null) {
          await _transactionService.markSyncFailed(tx.id, 'No group key');
          continue;
        }
        await _transactionService.markSyncing(tx.id);
        final bytes = await SyncEnvelope.seal(
          type: SyncPayloadType.transaction,
          groupId: tx.groupId,
          plaintextJson: tx.toJson(),
          groupKey: key,
        );
        final cid = await _ipfsService.addData(bytes);
        await _transactionService.markSynced(tx.id, cid);
        await _ipfsService.pin(cid);
        await _announce(tx.groupId, 'tx', cid);
        _log(SyncEvent(type: SyncEventType.transactionSynced, message: 'Transaction ${tx.id} → $cid'));
      } catch (e) {
        await _transactionService.markSyncFailed(tx.id, e.toString());
        _log(SyncEvent(type: SyncEventType.error, message: 'Failed to sync transaction ${tx.id}: $e'));
      }
    }
  }

  /// Notification: a CID, the group id (both opaque) and where to reach us so
  /// the receiver can dial back before fetching.
  Future<void> _announce(String groupId, String kind, String cid) async {
    if (!_subscribedGroups.contains(groupId)) {
      await _ipfsService.subscribe(topicFor(groupId));
      _subscribedGroups.add(groupId);
    }
    final known = await _peerBook.addrsFor(groupId);
    await _dialKnownPeers(groupId);
    // Relays get the block itself (they cannot dial back to fetch it); members
    // get the nudge and fetch from us or from a relay.
    await _pushToRelays(groupId, cid);
    final delivered = await _ipfsService.publish(
      topicFor(groupId),
      jsonEncode({'v': 1, 'kind': kind, 'groupId': groupId, 'cid': cid, 'addrs': dialableAddresses}),
      peers: {...known.map(PeerBook.peerIdOf), ...await _relayPeerIds()},
    );
    _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Announced $kind $cid to $delivered peer(s)'));
  }

  // ---------------------------------------------------------------------------
  // Inbound
  // ---------------------------------------------------------------------------

  Future<void> _onPubSubMessage(PubSubMessage msg) async {
    Map<String, dynamic> note;
    try {
      note = jsonDecode(msg.content) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final groupId = note['groupId'] as String?;
    final cid = note['cid'] as String?;
    if (groupId == null || cid == null) return;
    if (msg.topic != topicFor(groupId)) return;
    // Peers may hold two connections to us and notify over both.
    if (!_seenNotifications.add(cid)) return;
    if (_seenNotifications.length > 500) _seenNotifications.remove(_seenNotifications.first);
    _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Notified of ${note['kind']} $cid from ${msg.sender}'));

    try {
      // Make sure we hold a connection to the sender before asking bitswap,
      // which only talks to peers the router currently lists as connected.
      final addrs = (note['addrs'] as List?)?.cast<String>() ?? const [];
      if (addrs.isNotEmpty) await _peerBook.remember(groupId, addrs, exceptPeerId: _ownPeerId);
      await _dialKnownPeers(groupId);
      await _fetchAndApply(groupId, cid, from: msg.sender);
      // A notification proves the sender is reachable: use the moment to pick
      // up anything of theirs we missed (notifications are best effort).
      await _pullInventory(groupId);
    } catch (e) {
      _log(SyncEvent(type: SyncEventType.error, message: 'Rejected ${note['kind']} $cid: $e'));
    }
  }

  /// Fetches [cid]: local store, then the group's known vBank peers directly
  /// (plus [extraPeers], typically whoever announced it), then bitswap.
  Future<Uint8List?> _getData(String groupId, String cid, {Iterable<String> extraPeers = const []}) async {
    final sw = Stopwatch()..start();
    final local = await _ipfsService.getDataLocal(cid);
    if (local != null) return local;
    extraPeers = {...extraPeers, ...await _relayPeerIds()};
    final known = (await _peerBook.addrsFor(groupId)).map(PeerBook.peerIdOf);
    final peers = {...extraPeers, ...known}.toList();
    final direct = await _ipfsService.fetchFromPeers(cid, peers);
    if (direct != null) {
      _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Fetched $cid directly in ${sw.elapsedMilliseconds} ms'));
      return direct;
    }
    _log(SyncEvent(type: SyncEventType.warning, message: 'Direct fetch of $cid from ${peers.length} peer(s) failed after ${sw.elapsedMilliseconds} ms; trying bitswap'));
    final viaBitswap = await _ipfsService.getData(cid);
    _log(SyncEvent(
      type: viaBitswap == null ? SyncEventType.error : SyncEventType.peersDiscovered,
      message: 'Bitswap ${viaBitswap == null ? 'missed' : 'fetched'} $cid after ${sw.elapsedMilliseconds} ms',
    ));
    return viaBitswap;
  }

  Future<void> _fetchAndApply(String groupId, String cid, {String? from}) async {
    final key = await _groupKeyService.getKey(groupId);
    if (key == null) return;

    final extra = from == null ? const <String>[] : [from];
    var bytes = await _getData(groupId, cid, extraPeers: extra);
    if (bytes == null) {
      // Connections die without the router noticing, both ways. Reconnect to
      // everyone we know for this group and ask once more before giving up.
      await _dialKnownPeers(groupId, force: true);
      bytes = await _getData(groupId, cid, extraPeers: extra);
    }
    if (bytes == null) throw StateError('CID $cid not found');

    final envelope = SyncEnvelope.tryDecode(bytes);
    if (envelope == null) throw StateError('Not a vBank envelope');
    if (envelope.groupId != groupId) throw StateError('Envelope group mismatch');

    final payload = await envelope.open(key);

    switch (envelope.type) {
      case SyncPayloadType.transaction:
        await _applyTransaction(groupId, payload, cid);
        break;
      case SyncPayloadType.groupSnapshot:
        await _applySnapshot(payload, cid);
        break;
      case SyncPayloadType.memberJoin:
        await _applyMemberJoin(groupId, payload);
        break;
      case SyncPayloadType.loan:
        await _applyLoan(groupId, payload);
        break;
      case SyncPayloadType.meeting:
        await _applyMeeting(groupId, payload);
        break;
      case SyncPayloadType.reversal:
        await _applyReversal(groupId, payload);
        break;
    }
    await _ledger.record(groupId, cid);
  }

  /// Looks up the member the sync layer will trust as the author of a record.
  /// Must be a known, active owner/admin (DESIGN_PLAN §13 "verify signer's
  /// role before accepting").
  Future<Member> _requireRemoteWriter(String groupId, String peerId) async {
    final m = await _groupService.getMember(groupId, peerId);
    if (m == null || m.status != MemberStatus.active) {
      throw StateError('$peerId is not an active member');
    }
    if (!_groupService.canWrite(m.role)) {
      throw StateError('$peerId is not an owner/admin');
    }
    return m;
  }

  Future<void> _applyTransaction(String groupId, Map<String, dynamic> json, String cid) async {
    final tx = Transaction.fromJson(json);
    if (tx.groupId != groupId) throw StateError('Transaction group mismatch');
    final author = await _requireRemoteWriter(groupId, tx.authorPeerId);

    final outcome = await _transactionService.importRemote(tx, authorPublicKey: author.publicKey, cid: cid);
    if (outcome != TransactionService.importedNew) return;

    if (tx.type == TransactionType.repayment && tx.loanId != null) {
      await _loanService.applyRemoteRepayment(tx.loanId!, tx.amount);
    }
    _log(SyncEvent(type: SyncEventType.transactionReceived,
        message: 'Received ${tx.type.name} ${tx.amount} in $groupId'));
    final group = await _groupService.getGroup(groupId);
    String nameOf(String peerId) =>
        group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? (peerId == 'group' ? 'the group fund' : 'a member');
    final amount = '${tx.currency} ${tx.amount.toStringAsFixed(2)}';
    final body = switch (tx.type) {
      TransactionType.contribution => '${nameOf(tx.fromPeerId)} contributed $amount',
      TransactionType.repayment => '${nameOf(tx.fromPeerId)} repaid $amount',
      TransactionType.loan => '${nameOf(tx.toPeerId)} received a loan of $amount',
      TransactionType.withdrawal => '${nameOf(tx.toPeerId)} withdrew $amount',
      TransactionType.penalty => '${nameOf(tx.fromPeerId)} was charged a penalty of $amount',
      TransactionType.fee => '${nameOf(tx.fromPeerId)} paid a fee of $amount',
      TransactionType.reversal => 'A transaction of $amount was reversed',
    };
    _emitChange(SyncChange(
      SyncChangeType.transaction,
      groupId,
      recordId: tx.id,
      title: '${_titleCase(tx.type.name)} · ${group?.name ?? 'group'}',
      body: body,
    ));
  }

  Future<void> _applySnapshot(Map<String, dynamic> json, String cid) async {
    final groupId = (json['group'] as Map?)?['id'] as String?;
    final addrs = (json['publisherAddrs'] as List?)?.cast<String>() ?? const [];
    if (groupId != null && addrs.isNotEmpty) {
      await _peerBook.remember(groupId, addrs, exceptPeerId: _ownPeerId);
    }
    final result = await _groupService.importSnapshot(json, cid: cid, ownPeerId: _ownPeerId);
    if (!result.applied) return;
    // If ownership was just handed to us, countersign and republish.
    final me = _ownPeerId;
    final kp = _ownKeyPair;
    if (me != null && kp != null) {
      final signed = await _groupService.countersignTransfer(groupId: result.group.id, ownPeerId: me, ownKeyPair: kp);
      if (signed) await publishGroupSnapshot(result.group.id);
    }
    _emitChange(SyncChange(SyncChangeType.group, result.group.id));
  }

  static List<int> joinSigningPayload(String groupId, String peerId, String inviteId) =>
      utf8.encode('vbank:join:$groupId:$peerId:$inviteId');

  /// A new member announced themselves with an invite. Admin devices verify
  /// the invite (one-use, expiry, inviter signature), add the member, mark the
  /// invite used and republish (DESIGN_PLAN §16).
  Future<void> _applyMemberJoin(String groupId, Map<String, dynamic> json) async {
    final member = Member.fromJson(json['member'] as Map<String, dynamic>);
    final joinerAddrs = (json['addrs'] as List?)?.cast<String>() ?? const [];
    if (joinerAddrs.isNotEmpty) await _peerBook.remember(groupId, joinerAddrs, exceptPeerId: _ownPeerId);
    final signature = (json['signature'] as List).cast<int>();
    final inviteId = json['inviteId'] as String?;
    final nonceB64 = json['nonce'] as String?;
    if (inviteId == null || nonceB64 == null) throw StateError('Join without invite');

    final ok = await SigningService.verifyWithBytes(
      joinSigningPayload(groupId, member.peerId, inviteId), signature, member.publicKey);
    if (!ok) throw StateError('Invalid join signature from ${member.peerId}');

    final group = await _groupService.getGroup(groupId);
    if (group == null) return;
    final me = group.members.where((m) => m.peerId == _ownPeerId).firstOrNull;
    final iAmAdmin = me != null && me.status == MemberStatus.active && _groupService.canManageMembers(me.role);
    if (!iAmAdmin) return; // only admins act on joins; they'll republish the roster

    final invite = await _inviteService.getById(inviteId);
    if (invite == null) throw StateError('Unknown invite $inviteId');
    final inviter = invite.inviterPeerId == null ? null : await _groupService.getMember(groupId, invite.inviterPeerId!);
    if (inviter == null || !_groupService.canWrite(inviter.role)) {
      throw StateError('Invite was not issued by an owner/admin');
    }
    await InviteService.verify(
      invite,
      groupId: groupId,
      presentedNonce: base64Decode(nonceB64),
      inviterPublicKey: inviter.publicKey,
    );

    final existing = await _groupService.getMember(groupId, member.peerId);
    if (existing == null) {
      await _groupService.addMember(
        groupId: groupId,
        member: Member(
          peerId: member.peerId,
          name: member.name,
          role: MemberRole.member, // never trust a self-declared role
          joinedAt: member.joinedAt,
          publicKey: member.publicKey,
          status: group.requireApproval ? MemberStatus.pending : MemberStatus.active,
        ),
      );
    }
    await _inviteService.markUsed(inviteId, member.peerId);
    _log(SyncEvent(type: SyncEventType.memberJoined, message: '${member.name} joined ${group.name}'));
    _emitChange(SyncChange(
      SyncChangeType.member,
      groupId,
      recordId: member.peerId,
      title: group.requireApproval ? 'Join request · ${group.name}' : 'New member · ${group.name}',
      body: group.requireApproval
          ? '${member.name} is waiting for approval in ${group.name}'
          : '${member.name} joined ${group.name}',
    ));
    await publishGroupSnapshot(groupId);
  }

  Future<void> _applyLoan(String groupId, Map<String, dynamic> json) async {
    final loan = LoanRequest.fromJson(json);
    if (loan.groupId != groupId) throw StateError('Loan group mismatch');
    final borrower = await _groupService.getMember(groupId, loan.borrowerPeerId);
    if (borrower == null) throw StateError('Unknown borrower');
    if (!await _loanService.verifyRequestSignature(loan, borrower.publicKey)) {
      throw StateError('Invalid borrower signature');
    }
    if (loan.status != LoanStatus.pending) {
      final approverId = loan.approvedByPeerId;
      if (approverId == null) throw StateError('Approved loan without approver');
      // Auto-approved loans (requireLoanApproval = false) are self-approved.
      final approver = approverId == loan.borrowerPeerId
          ? borrower
          : await _requireRemoteWriter(groupId, approverId);
      if (!await _loanService.verifyApprovalSignature(loan, approver.publicKey)) {
        throw StateError('Invalid approver signature');
      }
    }
    await _loanService.importRemote(loan);
    _emitChange(SyncChange(
      SyncChangeType.loan,
      groupId,
      recordId: loan.id,
      title: 'Loan ${loan.status.name} · ${(await _groupService.getGroup(groupId))?.name ?? 'group'}',
      body: '${borrower.name} · ${loan.requestedAmount.toStringAsFixed(2)} over ${loan.termWeeks} weeks',
    ));
  }

  Future<void> _applyMeeting(String groupId, Map<String, dynamic> json) async {
    final publisher = json['publisher'] as String?;
    final signature = (json['signature'] as List?)?.cast<int>();
    final meetingJson = json['meeting'] as Map<String, dynamic>?;
    if (publisher == null || signature == null || meetingJson == null) {
      throw StateError('Meeting record is unsigned');
    }
    final author = await _requireRemoteWriter(groupId, publisher);
    final ok = await SigningService.verifyWithBytes(
      utf8.encode(jsonEncode(meetingJson)), signature, author.publicKey);
    if (!ok) throw StateError('Invalid meeting signature');
    final meeting = Meeting.fromJson(meetingJson);
    if (meeting.groupId != groupId) throw StateError('Meeting group mismatch');
    await _meetingService.importRemote(meeting);
    _emitChange(SyncChange(
      SyncChangeType.meeting,
      groupId,
      recordId: meeting.id,
      title: 'Meeting ${meeting.status.name} · ${(await _groupService.getGroup(groupId))?.name ?? 'group'}',
      body: _fmtWhen(meeting.scheduledAt.toLocal()),
    ));
  }

  /// Meetings are signed by the admin who publishes them.
  Future<void> publishSignedMeeting(Meeting m) async {
    final kp = _ownKeyPair;
    final me = _ownPeerId;
    if (kp == null || me == null) throw StateError('Not signed in');
    final meetingJson = m.toJson();
    final sig = await SigningService.sign(utf8.encode(jsonEncode(meetingJson)), kp);
    await publishRecord(m.groupId, SyncPayloadType.meeting, {
      'v': 1,
      'meeting': meetingJson,
      'publisher': me,
      'signature': sig.bytes,
    });
  }

  Future<void> _applyReversal(String groupId, Map<String, dynamic> json) async {
    final r = TransactionReversal.fromJson(json);
    if (r.groupId != groupId) throw StateError('Reversal group mismatch');
    await _governanceService.importRemote(r);
    _emitChange(SyncChange(
      SyncChangeType.reversal,
      groupId,
      recordId: r.originalTransactionId,
      title: 'Reversal ${r.status.name}',
      body: r.reason,
    ));
  }

  // ---------------------------------------------------------------------------
  // Joining (DESIGN_PLAN §16 + §12)
  // ---------------------------------------------------------------------------

  Future<Group> joinGroup({
    required String groupId,
    required String? groupCid,
    required String? inviteId,
    required String? inviteNonceB64,
    required Member self,
    required SimpleKeyPair keyPair,
    String? passphrase,
    String? inviteSecretB64,
    String? inviterPeerId,
    List<String> inviterAddrs = const [],
    bool parkIfUnreachable = true,
  }) async {
    if (inviteSecretB64 == null) {
      if (passphrase == null) throw const JoinGroupException('This invite link needs the group passphrase');
      final passphraseError = GroupKeyService.validatePassphrase(passphrase);
      if (passphraseError != null) throw JoinGroupException(passphraseError);
    }
    if (groupCid == null || groupCid.isEmpty || inviteId == null || inviteNonceB64 == null) {
      throw const JoinGroupException(
        'This invite link is incomplete or from an older version. Ask the inviter '
        'to share a new link from the Invite screen.',
      );
    }
    try {
      await _ensureNode();
    } catch (e) {
      throw JoinGroupException('Could not start the network node: $e');
    }
    if (!_joiningGroups.add(groupId)) throw const JoinGroupException('Already joining this group');
    try {
      // Legacy links: the key is derived from the shared passphrase up front.
      // Invite-secret links: the key is unwrapped from the snapshot once fetched.
      final key = inviteSecretB64 == null ? await GroupKeyService.deriveKey(passphrase!, groupId) : null;
      // The invite link carries the addresses of the inviter and of other
      // members: dial them before asking, bitswap only talks to peers we are
      // already connected to.
      if (inviterAddrs.isNotEmpty) {
        await _peerBook.remember(groupId, inviterAddrs, exceptPeerId: _ownPeerId);
      }
      final bytes = await _fetchSnapshot(groupId, groupCid, inviterAddrs.map(PeerBook.peerIdOf).toSet());
      if (bytes == null) {
        if (!parkIfUnreachable) {
          throw const JoinGroupException(
            'Timed out fetching the group from the network. Make sure a member\'s '
            'phone is online (or on the same Wi-Fi) and try again.',
          );
        }
        await _pendingJoins.put(PendingJoin(
          groupId: groupId,
          groupCid: groupCid,
          inviteId: inviteId,
          inviteNonceB64: inviteNonceB64,
          inviterPeerId: inviterPeerId,
          addrs: inviterAddrs,
          keyB64: key == null ? null : base64Encode(await key.extractBytes()),
          inviteSecretB64: inviteSecretB64,
          self: self,
          createdAt: DateTime.now().toUtc(),
        ));
        _log(SyncEvent(type: SyncEventType.warning, message: 'Nobody reachable for $groupId — join parked'));
        throw const JoinParkedException();
      }
      final group = await _completeJoin(
        bytes: bytes,
        key: key,
        inviteSecretB64: inviteSecretB64,
        self: self,
        keyPair: keyPair,
        groupId: groupId,
        groupCid: groupCid,
        inviteId: inviteId,
        inviteNonceB64: inviteNonceB64,
      );
      await _pendingJoins.remove(groupId);
      return group;
    } finally {
      _joiningGroups.remove(groupId);
    }
  }

  /// Dials what we know for [groupId] and fetches the snapshot [cid] from any
  /// connected member. Null when nobody answered in time.
  Future<Uint8List?> _fetchSnapshot(
    String groupId,
    String cid,
    Set<String> peerIds, {
    Duration timeout = const Duration(seconds: 45),
  }) async {
    peerIds = {...peerIds, ...await _relayPeerIds()}..remove(_ownPeerId);
    await _dialRelays();
    await _dialKnownPeers(groupId);
    var up = await _awaitAnyConnected(peerIds);
    if (up.isEmpty && peerIds.isNotEmpty) {
      // One redial, then give up quickly: with no member connected neither a
      // direct fetch nor bitswap can succeed, and the caller parks the join.
      await _dialKnownPeers(groupId, force: true);
      up = await _awaitAnyConnected(peerIds);
      if (up.isEmpty) {
        _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'No member reachable for $groupId'));
        return null;
      }
    }
    _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Reachable members before fetch: ${up.length}'));
    try {
      var bytes = await _getData(groupId, cid, extraPeers: up).timeout(timeout);
      if (bytes == null && peerIds.isNotEmpty) {
        // The connection can be dropped underneath us (see PeerBook.remember);
        // one redial covers the common case.
        await _dialKnownPeers(groupId, force: true);
        up = await _awaitAnyConnected(peerIds);
        if (up.isNotEmpty) bytes = await _getData(groupId, cid, extraPeers: up).timeout(timeout);
      }
      _log(SyncEvent(type: SyncEventType.peersDiscovered, message: 'Fetched $cid: ${bytes?.length ?? 'null'} bytes'));
      return bytes;
    } on TimeoutException {
      return null;
    }
  }

  /// Verifies, imports and announces a join once the snapshot bytes are here.
  /// Every failure in here is permanent for this invite/passphrase pair.
  Future<Group> _completeJoin({
    required Uint8List bytes,
    SecretKey? key,
    String? inviteSecretB64,
    required Member self,
    required SimpleKeyPair keyPair,
    required String groupId,
    required String groupCid,
    required String inviteId,
    required String inviteNonceB64,
  }) async {
    final envelope = SyncEnvelope.tryDecode(bytes);
    if (envelope == null || envelope.type != SyncPayloadType.groupSnapshot || envelope.groupId != groupId) {
      throw const JoinGroupException('Invite does not point at a valid group');
    }
    if (key == null) {
      // Invite-secret link: the snapshot header carries the group key wrapped
      // under this invite's secret — only while the invite is live.
      final wrapped = envelope.wraps[inviteId];
      if (wrapped == null) {
        throw const JoinGroupException(
          'This invite has been used or has expired. Ask a group admin for a new invite link.',
        );
      }
      key = await InviteKeyWrap.unwrap(
        wrapped: wrapped,
        secret: InviteKeyWrap.decodeSecret(inviteSecretB64!),
        groupId: groupId,
        inviteId: inviteId,
      );
      if (key == null) throw const JoinGroupException('Invite link is damaged — ask for a new one');
    }
    Map<String, dynamic> snapshot;
    try {
      snapshot = await envelope.open(key);
    } on EnvelopeAuthException {
      throw const JoinGroupException('Wrong group passphrase');
    }
    // Validate the invite against the roster *before* touching local state.
    final incomingGroup = Group.fromJson(snapshot['group'] as Map<String, dynamic>);
    final invites = ((snapshot['invites'] as List?) ?? const [])
        .map((j) => InviteService.fromSnapshotJson(j as Map<String, dynamic>))
        .toList();
    final invite = invites.where((i) => i.id == inviteId).firstOrNull;
    if (invite == null) throw const JoinGroupException('Invite not recognised by the group');
    final inviter = incomingGroup.members.where((m) => m.peerId == invite.inviterPeerId).firstOrNull;
    if (inviter == null || !_groupService.canWrite(inviter.role)) {
      throw const JoinGroupException('Invite was not issued by a group admin');
    }
    try {
      await InviteService.verify(
        invite,
        groupId: groupId,
        presentedNonce: base64Decode(inviteNonceB64),
        inviterPublicKey: inviter.publicKey,
      );
    } on InviteException catch (e) {
      throw JoinGroupException(e.message);
    }
    SnapshotImportResult result;
    try {
      result = await _groupService.importSnapshot(snapshot, cid: groupCid, ownPeerId: self.peerId);
    } catch (e) {
      throw JoinGroupException('Group data failed verification: $e');
    }
    await _groupKeyService.setKey(groupId, key);
    await _ledger.record(groupId, groupCid);

    final me = Member(
      peerId: self.peerId,
      name: self.name,
      role: MemberRole.member,
      joinedAt: self.joinedAt,
      publicKey: self.publicKey,
      status: result.group.requireApproval ? MemberStatus.pending : MemberStatus.active,
    );
    await _groupService.addMember(groupId: groupId, member: me, bumpSequence: false);

    final signature = await SigningService.sign(joinSigningPayload(groupId, self.peerId, inviteId), keyPair);
    await publishRecord(groupId, SyncPayloadType.memberJoin, {
      'v': 2,
      'member': me.toJson(),
      'inviteId': inviteId,
      'nonce': inviteNonceB64,
      'signature': signature.bytes,
      'addrs': dialableAddresses,
    });

    _log(SyncEvent(type: SyncEventType.memberJoined, message: 'Joined ${result.group.name}'));
    return (await _groupService.getGroup(groupId)) ?? result.group;
  }

  // ---------------------------------------------------------------------------
  // Parked joins
  // ---------------------------------------------------------------------------

  Future<List<PendingJoin>> pendingJoins() => _pendingJoins.all();

  Future<void> cancelPendingJoin(String groupId) async {
    await _pendingJoins.remove(groupId);
    await _peerBook.forget(groupId);
  }

  /// Replaces the key of a parked join (after "Wrong group passphrase") and
  /// tries again right away.
  Future<void> updatePendingJoinPassphrase(String groupId, String passphrase) async {
    final error = GroupKeyService.validatePassphrase(passphrase);
    if (error != null) throw JoinGroupException(error);
    final current = await _pendingJoins.get(groupId);
    if (current == null) return;
    final key = await GroupKeyService.deriveKey(passphrase, groupId);
    await _pendingJoins.put(current.copyWith(
      keyB64: base64Encode(await key.extractBytes()),
      clearError: true,
      permanent: false,
    ));
    await retryPendingJoinsNow();
  }

  bool _retryingJoins = false;

  /// Tries every parked join whose peers are not all in dial backoff. Cheap
  /// when nobody is home: a dial, a 3 s wait, done. Called after each sync
  /// round and by the "Retry now" action.
  Future<void> retryPendingJoinsNow() async {
    if (_retryingJoins) return;
    _retryingJoins = true;
    try {
      final joins = await _pendingJoins.all();
      if (joins.isEmpty) return;
      final me = _ownPeerId;
      final kp = _ownKeyPair;
      if (me == null || kp == null) return;
      final now = DateTime.now();
      for (final j in joins) {
        if (j.self.peerId != me) {
          // A different account than the one that parked it: drop it.
          await _pendingJoins.remove(j.groupId);
          continue;
        }
        if (!j.shouldAttempt(now, _dialBackoffUntil)) continue;
        if (!_joiningGroups.add(j.groupId)) continue;
        try {
          await _retryPendingJoin(j, kp);
        } finally {
          _joiningGroups.remove(j.groupId);
        }
      }
    } catch (e) {
      _log(SyncEvent(type: SyncEventType.warning, message: 'Retrying parked joins failed: $e'));
    } finally {
      _retryingJoins = false;
    }
  }

  Future<void> _retryPendingJoin(PendingJoin j, SimpleKeyPair kp) async {
    try {
      await _ensureNode();
    } catch (_) {
      return; // no node, nothing to do this round
    }
    if (j.addrs.isNotEmpty) await _peerBook.remember(j.groupId, j.addrs, exceptPeerId: _ownPeerId);
    final peers = {...j.peerIds, ...(await _peerBook.addrsFor(j.groupId)).map(PeerBook.peerIdOf), ...await _relayPeerIds()}
      ..remove(_ownPeerId);
    await _dialRelays();
    await _dialKnownPeers(j.groupId);
    final up = await _awaitAnyConnected(peers);
    if (up.isEmpty) {
      for (final p in peers) {
        _peerFailed(p);
      }
      await _pendingJoins.put(j.copyWith(attempts: j.attempts + 1, lastError: 'No member online'));
      _log(SyncEvent(type: SyncEventType.warning, message: 'Parked join ${j.groupId}: no member online (attempt ${j.attempts + 1})'));
      return;
    }
    Uint8List? bytes;
    try {
      bytes = await _getData(j.groupId, j.groupCid, extraPeers: up).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      bytes = null;
    }
    if (bytes == null) {
      await _pendingJoins.put(j.copyWith(attempts: j.attempts + 1, lastError: 'A member is online but did not answer'));
      _log(SyncEvent(type: SyncEventType.warning, message: 'Parked join ${j.groupId}: fetch failed (attempt ${j.attempts + 1})'));
      return;
    }
    try {
      final group = await _completeJoin(
        bytes: bytes,
        key: j.keyBytes == null ? null : SecretKey(j.keyBytes!),
        inviteSecretB64: j.inviteSecretB64,
        self: j.self,
        keyPair: kp,
        groupId: j.groupId,
        groupCid: j.groupCid,
        inviteId: j.inviteId,
        inviteNonceB64: j.inviteNonceB64,
      );
      await _pendingJoins.remove(j.groupId);
      _emitChange(SyncChange(
        SyncChangeType.group,
        j.groupId,
        title: 'Joined ${group.name}',
        body: group.requireApproval ? 'Waiting for an admin to approve you' : 'You are now a member',
      ));
    } on JoinGroupException catch (e) {
      // Fetch worked, the invite or passphrase did not: retrying cannot help.
      await _pendingJoins.put(j.copyWith(attempts: j.attempts + 1, lastError: e.message, permanent: true));
      _log(SyncEvent(type: SyncEventType.error, message: 'Parked join ${j.groupId} failed: ${e.message}'));
      _emitChange(SyncChange(SyncChangeType.group, j.groupId, title: 'Could not join a group', body: e.message));
    } catch (e) {
      await _pendingJoins.put(j.copyWith(attempts: j.attempts + 1, lastError: '$e'));
      _log(SyncEvent(type: SyncEventType.warning, message: 'Parked join ${j.groupId}: $e'));
    }
  }

  /// Creates a signed invite and returns the deep-link parameters
  /// (`cid`, `invite`, `n`). Owner/admin only.
  Future<CreatedInvite> createInvite(String groupId) async {
    final me = _ownPeerId;
    final kp = _ownKeyPair;
    if (me == null || kp == null) throw StateError('Not signed in');
    await _groupService.requireWriter(groupId, me);
    final created = await _inviteService.createInvite(
      groupId: groupId,
      groupCid: '',
      inviterPeerId: me,
      inviterKeyPair: kp,
      groupKey: await _groupKeyService.requireKey(groupId),
    );
    // The snapshot must carry the invite (and its wrapped key) so joiners can
    // open and validate it.
    final cid = await publishGroupSnapshot(groupId);
    final invite = created.invite;
    final withCid = InviteData(
      id: invite.id,
      groupId: invite.groupId,
      cid: cid,
      createdAt: invite.createdAt,
      expiresAt: invite.expiresAt,
      nonce: invite.nonce,
      inviterPeerId: invite.inviterPeerId,
      inviterSignature: invite.inviterSignature,
      wrappedKey: invite.wrappedKey,
    );
    await _inviteService.upsert(withCid);
    return CreatedInvite(withCid, created.secret);
  }

  // ---------------------------------------------------------------------------

  void _emitChange(SyncChange change) {
    if (!_changesController.isClosed) _changesController.add(change);
  }

  void _setState(SyncState newState) {
    _state = newState;
    // An in-flight sync can report progress while the app is shutting down and
    // the controllers have already been closed.
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  static String _titleCase(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  /// "Tue 2 Sep, 09:00" — no locale data needed.
  static String _fmtWhen(DateTime t) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${days[t.weekday - 1]} ${t.day} ${months[t.month - 1]}, $hh:$mm';
  }

  void _log(SyncEvent event) {
    // Visible in debug and profile builds (the two-device E2E runs a profile
    // build on the phone); compiled out of release.
    if (kDebugMode || kProfileMode) debugPrint('[sync] ${event.type.name}: ${event.message}');
    _recentLog.insert(0, event);
    if (_recentLog.length > _maxLog) _recentLog.removeLast();
    if (!_syncLogController.isClosed) _syncLogController.add(event);
  }

  bool get shouldSync {
    if (_lastSyncTime == null) return true;
    return DateTime.now().difference(_lastSyncTime!) > _syncInterval;
  }

  void setSyncInterval(Duration interval) {
    _syncInterval = interval;
    if (_periodicSyncTimer != null) startPeriodicSync(interval: interval);
  }

  void dispose() {
    stopPeriodicSync();
    _backgroundStopTimer?.cancel();
    _pubsubSub?.cancel();
    _stateController.close();
    _syncLogController.close();
    _changesController.close();
  }
}

enum SyncEventType {
  started, stopped, completed, error,
  /// Transient: a peer unreachable right now, a dial that timed out. Shown in
  /// amber; the next round usually clears it.
  warning,
  nodeStarted, nodeStopped, syncStarted, transactionSynced, transactionReceived,
  snapshotPublished, memberJoined, peersDiscovered,
}

class SyncEvent {
  final SyncEventType type;
  final String message;
  final DateTime timestamp;

  SyncEvent({required this.type, required this.message, DateTime? timestamp})
      : timestamp = timestamp ?? DateTime.now().toUtc();
}
