import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../crypto/sync_envelope.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/group.dart';
import '../crypto/invite_wrap.dart';
import '../crypto/signing.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import '../sync/engine.dart';
import '../sync/ledger.dart';
import '../sync/peer_book.dart';
import '../sync/relay_directory.dart';
import '../sync/record_codec.dart';
import '../sync/sync_node.dart';
import 'apply_pipeline.dart';
import 'context.dart';
import 'governance_service.dart';
import 'group_service.dart';
import 'invite_link.dart';
import 'invite_service.dart';
import 'signing_payloads.dart';
import 'key_service.dart';
import 'loan_service.dart';
import 'meeting_service.dart';
import 'publish_pipeline.dart';
import 'publish_reconciler.dart';
import 'publish_tracker.dart';
import 'transaction_service.dart';

/// Sync engine state for screens.
enum SyncState {
  /// Nothing running.
  idle,

  /// A round is running.
  syncing,

  /// The last round failed; see [SyncCoordinator.recentLog].
  error,
}

/// What happened, for the sync log and notifications UI.
enum SyncEventType {
  /// Node lifecycle.
  nodeStarted,

  /// A round began/completed.
  round,

  /// Peers, relays and records found.
  discovered,

  /// Something needs attention.
  warning,

  /// Something failed.
  error,
}

/// One log line.
final class SyncEvent {
  /// What kind.
  final SyncEventType type;

  /// Human line.
  final String message;

  /// When it happened.
  final DateTime at;

  /// Creates a log line.
  SyncEvent(this.type, this.message) : at = DateTime.now();
}

/// Something that arrived from a peer and changed local state. Screens
/// refresh on these; notifications raise them.
final class SyncChange {
  /// What kind of record moved.
  final SyncChangeType type;

  /// The group it belongs to.
  final String groupId;

  /// Record id (transaction, loan, meeting, reversal; member peer id for
  /// joins), for opening on tap.
  final String? recordId;

  /// Creates a change.
  const SyncChange(this.type, this.groupId, {this.recordId});
}

/// Record kinds that surface as changes.
enum SyncChangeType {
  /// A transaction landed or published.
  transaction,

  /// Group metadata changed.
  group,

  /// The roster changed.
  member,

  /// A loan changed state.
  loan,

  /// A meeting changed state.
  meeting,

  /// A reversal was requested or resolved.
  reversal,
}

/// Owns the sync engine, both pipelines and the transport: rounds,
/// announcements, notifications and the pending queue.
///
/// Lifecycle: [ensureStarted] brings the node up (idempotent) and
/// subscribes group topics; [synchronizeNow] runs one round now;
/// [startPeriodic]/[stopPeriodic] schedule rounds. Local changes publish
/// through [publishRecord]/[publishSnapshot]/[publishJoin]; failures park
/// in a pending set retried every round.
final class SyncCoordinator {
  /// P2P node (fake in tests).
  final SyncNode transport;

  /// Groups and roster.
  final GroupService groups;

  /// Application services for pipeline construction: transactions.
  final TransactionService transactions;

  /// Application services for pipeline construction: loans.
  final LoanService loans;

  /// Application services for pipeline construction: meetings.
  final MeetingService meetings;

  /// Application services for pipeline construction: governance.
  final GovernanceService governance;

  /// Application services for pipeline construction: invites.
  final InviteService invites;

  /// Record listings for the publish reconciler.
  final TransactionRepository transactionRepository;

  /// Loan listings for the publish reconciler.
  final LoanRepository loanRepository;

  /// Meeting listings for the publish reconciler.
  final MeetingRepository meetingRepository;

  /// Group keys.
  final GroupKeyService keys;

  /// Known member addresses.
  final PeerBook peers;

  /// Record inventories.
  final SyncLedger ledger;

  /// Built-in relay discovery.
  final RelayDirectory relays;

  /// Opaque settings (relay list, toggles, pending queue, snapshots).
  final SettingsRepository settings;

  /// Device signer for countersigning.
  final SignPayload sign;

  /// This device's peer id (identity), or null before sign-in.
  final String? Function() ownPeerId;

  /// This device's X25519 pair for rekeyed rings, or null to skip.
  final Future<SimpleKeyPair?> Function() memberKeyPair;

  /// This device's dialable addresses for snapshots and invites.
  final List<String> Function() ownAddrs;

  /// Identity keypair for snapshot and meeting signatures.
  final Future<SimpleKeyPair> Function() signingKey;

  /// Clock for scheduling.
  final AppClock clock;

  /// Round interval.
  Duration interval;

  /// Engine (built in [ensureStarted]).
  SyncEngine? _engine;

  /// Pipelines (built in [ensureStarted]).
  ApplyPipeline? _apply;
  PublishPipeline? _publish;

  /// Already-published record ids, shared by the apply pipeline (marks)
  /// and the reconciler (skips).
  late final PublishTracker tracker = PublishTracker(settings);

  /// Publishes local records the ledger does not know yet.
  PublishReconciler? _reconcile;

  /// Subscribed topics.
  final Set<String> _subscribed = {};

  /// CIDs announced this session (dedup).
  final Set<String> _seen = {};

  /// Round state.
  SyncState _state = SyncState.idle;

  /// Recent log, newest last, capped.
  final List<SyncEvent> recentLog = [];
  static const int _maxLog = 200;

  /// State changes.
  final StreamController<SyncState> _states =
      StreamController<SyncState>.broadcast();

  /// Log lines.
  final StreamController<SyncEvent> _log =
      StreamController<SyncEvent>.broadcast();

  /// Applied records.
  final StreamController<SyncChange> _changes =
      StreamController<SyncChange>.broadcast();

  /// Notification subscription.
  StreamSubscription<SyncNotification>? _notifySub;

  /// Periodic rounds.
  Timer? _periodic;

  /// A publish asked for while a round was busy; the round runs once more.
  bool _rerun = false;

  /// Serializes overlapping publish calls.
  Future<void> _publishing = Future.value();

  /// Creates the coordinator. Call [ensureStarted] before use.
  SyncCoordinator({
    required this.transport,
    required this.groups,
    required this.transactions,
    required this.loans,
    required this.meetings,
    required this.governance,
    required this.invites,
    required this.transactionRepository,
    required this.loanRepository,
    required this.meetingRepository,
    required this.keys,
    required this.peers,
    required this.ledger,
    required this.relays,
    required this.settings,
    required this.sign,
    required this.ownPeerId,
    required this.memberKeyPair,
    required this.ownAddrs,
    required this.signingKey,
    required this.clock,
    this.interval = const Duration(minutes: 2),
  });

  /// Current state.
  SyncState get state => _state;

  /// State changes.
  Stream<SyncState> get states => _states.stream;

  /// Log lines.
  Stream<SyncEvent> get log => _log.stream;

  /// Applied records.
  Stream<SyncChange> get changes => _changes.stream;

  /// Starts the node (idempotent), wires the engine and pipelines, and
  /// subscribes group topics.
  Future<void> ensureStarted() async {
    if (_engine != null) {
      return;
    }
    if (!transport.isRunning) {
      await transport.start();
      _emit(
        SyncEventType.nodeStarted,
        'Node started as ${transport.peerId}',
      );
    }
    final SyncEngine engine = SyncEngine(
      transport: transport,
      peerAddrsFor: peers.addrsFor,
      groupKeyFor: _groupKeyBytes,
      ledgerCids: ledger.cidsFor,
      ledgerRecord: ledger.record,
      applyBlock: (String groupId, String cid, Uint8List block) =>
          _applyViaPipeline(groupId, cid, block),
      localBlock: transport.localBlock,
      clock: clock,
    );
    transport.onRequest = engine.handleRequest;
    _engine = engine;
    _apply = ApplyPipeline(
      groups: groups,
      transactions: transactions,
      loans: loans,
      meetings: meetings,
      governance: governance,
      invites: invites,
      keys: keys,
      rememberAddrs: peers.remember,
      lastPublishedAt: _lastSnapshotAt,
      recordPublishedAt: _recordSnapshotAt,
      recordPublished: tracker.markPublished,
      ownPeerId: ownPeerId() ?? '',
      memberKeyPair: memberKeyPair,
      clock: clock,
    );
    final PublishPipeline publish = PublishPipeline(
      transport: transport,
      keys: keys,
      groups: groups,
      invites: invites,
      governance: governance,
      ledgerRecord: ledger.record,
      ownAddrs: ownAddrs,
      memberKeyPair: memberKeyPair,
      clock: clock,
    );
    _publish = publish..bindSigningKey(signingKey);
    _reconcile = PublishReconciler(
      groups: groups,
      inviteService: invites,
      governanceService: governance,
      transactions: transactionRepository,
      loans: loanRepository,
      meetings: meetingRepository,
      publish: publish,
      tracker: tracker,
      ledger: ledger,
      memberKeyPair: memberKeyPair,
      ownPeerId: ownPeerId,
    );
    final StreamSubscription<SyncNotification>? oldSub = _notifySub;
    _notifySub = null;
    await oldSub?.cancel();
    _notifySub = transport.notifications.listen(
      _onNotification,
      onError: (Object e) =>
          _emit(SyncEventType.error, 'Notifications: $e'),
    );
    await _subscribeAll();
  }

  /// One reconcile round over every keyed group now.
  Future<SyncReport> synchronizeNow() async {
    await ensureStarted();
    final SyncEngine engine = _engine!;
    if (_state == SyncState.syncing) {
      _rerun = true;
      return SyncReport.empty;
    }
    _setState(SyncState.syncing);
    try {
      final List<String> groupIds = await _keyedGroups();
      // Publish what the ledger does not know yet, so the round carries
      // local records to relays and the announcements pull peers.
      var published = 0;
      final PublishReconciler? reconcile = _reconcile;
      if (reconcile != null) {
        for (final String groupId in groupIds) {
          final List<(String, String)> fresh =
              await reconcile.publishMissing(groupId);
          published += fresh.length;
          for (final (String, String) announced in fresh) {
            await _announce(groupId, announced.$2, announced.$1);
          }
        }
      }
      final List<String> relayAddrs = await relayAddresses();
      await _dialRelays(relayAddrs);
      final SyncReport report = await engine.synchronize(
        groupIds: groupIds,
        relayAddrs: relayAddrs,
      );
      debugPrint(
        'vBank: sync round done '
        'groups=${groupIds.length} published=$published '
        'fetched=${report.fetched} applied=${report.applied} '
        'pushed=${report.pushed} relays=${relayAddrs.length} '
        'unreachable=${report.unreachable.length}',
      );
      for (final (String, String) applied in report.appliedCids) {
        _changes.add(
          SyncChange(
            SyncChangeType.transaction,
            applied.$1,
            recordId: applied.$2,
          ),
        );
      }
      _setState(SyncState.idle);
      if (_rerun) {
        _rerun = false;
        return synchronizeNow();
      }
      return report;
    } catch (e) {
      _setState(SyncState.error);
      _emit(SyncEventType.error, 'Round failed: $e');
      debugPrint('vBank: sync round failed: $e');
      rethrow;
    }
  }

  /// Schedules rounds every [interval].
  void startPeriodic({Duration? every}) {
    interval = every ?? interval;
    _periodic?.cancel();
    _periodic = Timer.periodic(interval, (_) async {
      if (_state != SyncState.syncing) {
        await synchronizeNow();
      }
    });
  }

  /// Stops scheduled rounds.
  void stopPeriodic() {
    _periodic?.cancel();
    _periodic = null;
  }

  /// Seals, stores, ledgers and announces a record. Relay delivery is
  /// reconciled on rounds, so a failed announce never loses the record.
  Future<Result<String>> publishRecord({
    required String groupId,
    required SyncPayloadType type,
    required Map<String, dynamic> payloadJson,
  }) async {
    final PublishPipeline? publish = _publish;
    if (publish == null) {
      return const Err(ValidationFailure('syncNotStarted'));
    }
    final Future<String> next =
        _publishing.then((_) => _publishAndAnnounce(
              publish,
              groupId,
              type,
              payloadJson,
            ));
    _publishing = next.then((_) {});
    try {
      final String cid = await next;
      // The reconciler would seal a duplicate next round; claim the id
      // now so each record is published exactly once.
      final Object? id = payloadJson['id'];
      if (id is String) {
        await tracker.markPublished(groupId, id);
      }
      return Ok(cid);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// Joins a group from a share link as [displayName]: fetches the
  /// snapshot the invite was cut against (directly, else the newest the
  /// relays hold), unwraps the group key with the link secret, applies
  /// the snapshot and announces the join. Idempotent: members rejoin
  /// silently. Bootstrap trusts the owner like any snapshot.
  Future<Result<Unit>> joinWithLink({
    required String link,
    required String displayName,
  }) async {
    await ensureStarted();
    final InviteLink? parts = InviteLink.tryParse(link.trim());
    if (parts == null) {
      return const Err(ValidationFailure('inviteLinkMalformed'));
    }
    if (parts.isExpiredAt(clock())) {
      return const Err(ValidationFailure('inviteExpired'));
    }
    final String? me = ownPeerId();
    if (me == null) {
      return const Err(ValidationFailure('syncNotSignedIn'));
    }
    if (displayName.trim().isEmpty) {
      return const Err(ValidationFailure('identityNameEmpty'));
    }
    final String groupId = parts.groupId;
    final Member? existing = await groups.getMember(groupId, me);
    if (existing != null && existing.status == MemberStatus.active) {
      return const Ok(unit);
    }
    final List<String> relayAddrs = await relayAddresses();
    if (relayAddrs.isEmpty) {
      return const Err(ValidationFailure('noRelays'));
    }
    final List<String> relayIds = [
      for (final String a in relayAddrs) PeerBook.peerIdOf(a),
    ];
    Uint8List? bytes = await transport.fetchBlock(
      parts.groupCid,
      relayIds,
    );
    debugPrint(
      'vBank: join fetch ${bytes == null ? 'miss' : 'hit'} '
      'cid=${parts.groupCid} relays=${relayIds.length}',
    );
    bytes ??= await _fetchNewestSnapshot(groupId, relayIds);
    if (bytes == null) {
      return const Err(ValidationFailure('snapshotUnreachable'));
    }
    final SyncEnvelope? header = SyncEnvelope.tryDecode(bytes);
    final Uint8List? wrapped = header?.wraps[parts.inviteId];
    if (header == null || wrapped == null) {
      return Err(NotFoundFailure('invite:${parts.inviteId}'));
    }
    final SecretKey? groupKey = await InviteKeyWrap.unwrap(
      wrapped: wrapped,
      secret: parts.secret,
      groupId: groupId,
      inviteId: parts.inviteId,
    );
    if (groupKey == null) {
      return Err(IntegrityFailure('invite:${parts.inviteId}'));
    }
    final Result<Unit> keyed = await keys.setKey(groupId, groupKey);
    if (keyed.isErr) {
      return Err(keyed.failure);
    }
    final ApplyOutcome outcome = await _applyViaPipeline(
      groupId,
      parts.groupCid,
      bytes,
    );
    if (outcome == ApplyOutcome.rejected) {
      return Err(IntegrityFailure('snapshot:$groupId'));
    }
    await ledger.record(groupId, parts.groupCid);
    final PublishPipeline? publish = _publish;
    if (publish == null) {
      return const Err(ValidationFailure('syncNotStarted'));
    }
    final SimpleKeyPair identity = await signingKey();
    final Uint8List publicKey = Uint8List.fromList(
      await SigningService.extractPublicKeyBytes(identity),
    );
    final Signature joinSig = await SigningService.sign(
      SigningPayloads.memberJoin(
        groupId: groupId,
        peerId: me,
        inviteId: parts.inviteId,
      ),
      identity,
    );
    final Result<String> cid = await publish.publishRaw(
      groupId: groupId,
      type: SyncPayloadType.memberJoin,
      payloadJson: {
        'member': RecordCodec.memberToJson(
          Member(
            peerId: me,
            name: displayName.trim(),
            joinedAt: clock(),
            publicKey: publicKey,
          ),
        ),
        'addrs': ownAddrs(),
        'signature': joinSig.bytes,
        'inviteId': parts.inviteId,
        'nonce': base64Encode(parts.nonce),
      },
    );
    if (cid.isErr) {
      return Err(cid.failure);
    }
    await _announce(groupId, SyncPayloadType.memberJoin.name, cid.value);
    return const Ok(unit);
  }

  /// Fetches the newest snapshot-shaped block the relays hold for
  /// [groupId]: asks each relay's inventory, opens candidates until one
  /// decodes as this group's snapshot.
  Future<Uint8List?> _fetchNewestSnapshot(
    String groupId,
    List<String> relayIds,
  ) async {
    for (final String relay in relayIds) {
      List<String>? cids;
      try {
        final Uint8List? reply = await transport.request(
          relay,
          Uint8List.fromList(
            utf8.encode(jsonEncode({'op': 'inventory', 'groupId': groupId})),
          ),
        );
        if (reply == null || reply.isEmpty) {
          continue;
        }
        cids = ((jsonDecode(utf8.decode(reply)) as Map)['cids'] as List)
            .cast<String>();
      } catch (_) {
        continue;
      }
      for (final String cid in cids.take(5)) {
        final Uint8List? bytes = await transport.fetchBlock(cid, [relay]);
        if (bytes == null) {
          continue;
        }
        final SyncEnvelope? header = SyncEnvelope.tryDecode(bytes);
        if (header != null &&
            header.groupId == groupId &&
            header.type == SyncPayloadType.groupSnapshot) {
          return bytes;
        }
      }
    }
    return null;
  }

  /// Publishes the group snapshot (roster, invites, governance).
  Future<Result<String>> publishSnapshot(String groupId) async {
    await ensureStarted();
    final PublishPipeline? publish = _publish;
    if (publish == null) {
      return const Err(ValidationFailure('syncNotStarted'));
    }
    final String? me = ownPeerId();
    if (me == null) {
      return const Err(ValidationFailure('syncNotSignedIn'));
    }
    final Result<String> cid = await publish.publishSnapshot(
      groupId: groupId,
      publisherPeerId: me,
    );
    if (cid.isErr) {
      return cid;
    }
    final PublishReconciler? reconcile = _reconcile;
    if (reconcile != null) {
      final Result<Group> group = await groups.getGroup(groupId);
      if (group.isOk) {
        final String? fingerprint = await reconcile.fingerprintOf(
          group.value,
        );
        if (fingerprint != null) {
          await tracker.recordSnapshotFingerprint(groupId, fingerprint);
        }
      }
    }
    await _announce(groupId, 'group', cid.value);
    return cid;
  }

  /// All relay addresses: user relays plus the built-in host when
  /// enabled (resolved live, falling back to the last good answer).
  Future<List<String>> relayAddresses() async {
    final List<String> out = [];
    final Result<Uint8List?> raw = await settings.get('relay.addrs');
    if (raw.isOk && raw.value != null) {
      try {
        out.addAll(
          (jsonDecode(utf8.decode(raw.value!)) as List).cast<String>(),
        );
      } catch (_) {}
    }
    if (await builtInRelayEnabled()) {
      for (final String host in kBuiltInRelayHosts) {
        final List<String> resolved = await relays.resolve(host);
        out.addAll(
          resolved.isNotEmpty ? resolved : await relays.loadKnown(host),
        );
      }
    }
    return out;
  }

  /// Whether the built-in relay is enabled (default true).
  Future<bool> builtInRelayEnabled() async {
    final Result<Uint8List?> raw = await settings.get('relay.builtin');
    if (raw.isOk && raw.value != null) {
      return utf8.decode(raw.value!) == '1';
    }
    return true;
  }

  /// Toggles the built-in relay.
  Future<void> setBuiltInRelayEnabled(bool enabled) => settings
      .set(
        'relay.builtin',
        Uint8List.fromList(utf8.encode(enabled ? '1' : '0')),
      )
      .then((_) {});

  /// Adds user relay addresses.
  Future<void> addRelays(Iterable<String> addrs) async {
    final Result<Uint8List?> raw = await settings.get('relay.addrs');
    final List<String> current = [];
    if (raw.isOk && raw.value != null) {
      try {
        current.addAll(
          (jsonDecode(utf8.decode(raw.value!)) as List).cast<String>(),
        );
      } catch (_) {}
    }
    for (final String a in addrs) {
      if (!current.contains(a)) {
        current.add(a);
      }
    }
    await settings.set(
      'relay.addrs',
      Uint8List.fromList(utf8.encode(jsonEncode(current))),
    );
  }

  /// Releases timers and subscriptions (not the transport).
  Future<void> dispose() async {
    stopPeriodic();
    await _notifySub?.cancel();
    await _states.close();
    await _log.close();
    await _changes.close();
  }

  // ------------------------------------------------------------ internals --

  /// Group key bytes for the engine, or null when keyless.
  Future<Uint8List?> _groupKeyBytes(String groupId) async {
    final SecretKey? key = await keys.getKey(groupId);
    if (key == null) {
      return null;
    }
    return Uint8List.fromList(await key.extractBytes());
  }

  /// Groups holding a key: the only ones that sync.
  Future<List<String>> _keyedGroups() async {
    final Result<List<Group>> all = await groups.listGroups();
    if (all.isErr) {
      return const [];
    }
    final List<String> keyed = [];
    for (final Group g in all.value) {
      if (await keys.hasKey(g.id)) {
        keyed.add(g.id);
      }
    }
    return keyed;
  }

  /// Best-effort dials so requests find live connections.
  Future<void> _dialRelays(List<String> relayAddrs) async {
    for (final String addr in relayAddrs) {
      try {
        await transport.connect(addr);
      } catch (_) {}
    }
  }

  /// Engine apply callback: delegates to the pipeline once built.
  Future<ApplyOutcome> _applyViaPipeline(
    String groupId,
    String cid,
    Uint8List block,
  ) async {
    final ApplyPipeline? apply = _apply;
    if (apply == null) {
      return ApplyOutcome.deferred;
    }
    return apply.apply(groupId, cid, block);
  }

  /// Announces a CID: subscribes the topic, pushes the block to relays
  /// (they cannot dial back), then publishes the nudge.
  Future<void> _announce(String groupId, String kind, String cid) async {
    final String topic = SyncEngine.topicFor(groupId);
    if (!_subscribed.contains(topic)) {
      try {
        await transport.subscribe(topic);
      } catch (_) {}
      _subscribed.add(topic);
    }
    final List<String> relayAddrs = await relayAddresses();
    final SyncEngine? engine = _engine;
    if (engine != null) {
      await engine.pushToRelays(
        groupId: groupId,
        cid: cid,
        relayAddrs: relayAddrs,
      );
    }
    final List<String> addrs = await peers.addrsFor(groupId);
    final Set<String> targets = {
      for (final String a in addrs) PeerBook.peerIdOf(a),
      for (final String a in relayAddrs) PeerBook.peerIdOf(a),
    };
    try {
      await transport.publish(
        topic,
        jsonEncode({
          'v': 1,
          'kind': kind,
          'groupId': groupId,
          'cid': cid,
          'addrs': ownAddrs(),
        }),
        targets.toList(),
      );
    } catch (_) {}
  }

  /// Handles one announcement: remembers return addresses, fetches and
  /// applies, then pulls the group to catch anything missed.
  Future<void> _onNotification(SyncNotification msg) async {
    Map<String, dynamic> note;
    try {
      note = jsonDecode(msg.content) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final String? groupId = note['groupId'] as String?;
    final String? cid = note['cid'] as String?;
    if (groupId == null || cid == null) {
      return;
    }
    if (msg.topic != SyncEngine.topicFor(groupId)) {
      return;
    }
    if (!_seen.add(cid)) {
      return;
    }
    if (_seen.length > 500) {
      _seen.remove(_seen.first);
    }
    final List<String> addrs =
        ((note['addrs'] as List?) ?? const []).cast<String>();
    if (addrs.isNotEmpty) {
      final String? me = ownPeerId();
      await peers.remember(groupId, addrs, exceptPeerId: me);
    }
    final SyncEngine? engine = _engine;
    if (engine == null) {
      return;
    }
    try {
      final Uint8List? bytes = await transport.fetchBlock(cid, [msg.sender]);
      if (bytes == null) {
        return;
      }
      final ApplyOutcome outcome =
          await _applyViaPipeline(groupId, cid, bytes);
      if (outcome == ApplyOutcome.applied) {
        await engine.ledgerRecord(groupId, cid);
        _changes.add(
          SyncChange(_changeTypeOf(note['kind']), groupId, recordId: cid),
        );
        await engine.synchronize(
          groupIds: [groupId],
          relayAddrs: await relayAddresses(),
        );
      }
    } catch (_) {}
  }

  /// Subscribes every keyed group's topic.
  Future<void> _subscribeAll() async {
    for (final String groupId in await _keyedGroups()) {
      final String topic = SyncEngine.topicFor(groupId);
      if (_subscribed.contains(topic)) {
        continue;
      }
      try {
        await transport.subscribe(topic);
      } catch (_) {}
      _subscribed.add(topic);
    }
  }

  /// Seals, stores, ledgers and announces one record. Returns its CID.
  Future<String> _publishAndAnnounce(
    PublishPipeline publish,
    String groupId,
    SyncPayloadType type,
    Map<String, dynamic> payloadJson,
  ) async {
    final Result<String> cid = await publish.publishRecord(
      groupId: groupId,
      type: type,
      payloadJson: payloadJson,
    );
    if (cid.isErr) {
      throw StateError('publish failed: ${cid.failure}');
    }
    await _announce(groupId, _announceKind(type), cid.value);
    return cid.value;
  }

  /// Last snapshot time for ordering, falling back to nothing.
  Future<DateTime?> _lastSnapshotAt(String groupId) async {
    final Result<Uint8List?> raw = await settings.get('snapshot.at.$groupId');
    if (raw.isErr || raw.value == null) {
      return null;
    }
    return DateTime.tryParse(utf8.decode(raw.value!))?.toUtc();
  }

  /// Records a snapshot time.
  Future<void> _recordSnapshotAt(String groupId, DateTime at) => settings
      .set(
        'snapshot.at.$groupId',
        Uint8List.fromList(utf8.encode(at.toIso8601String())),
      )
      .then((_) {});

  /// Announcement kinds mirror the legacy app: transactions announce as
  /// `'tx'`, everything else as the payload type name.
  static String _announceKind(SyncPayloadType type) =>
      type == SyncPayloadType.transaction ? 'tx' : type.name;

  /// Maps announcement kinds to change types.
  static SyncChangeType _changeTypeOf(Object? kind) => switch (kind) {
        'tx' || 'transaction' => SyncChangeType.transaction,
        'group' || 'groupSnapshot' => SyncChangeType.group,
        'member' || 'memberJoin' || 'memberKey' => SyncChangeType.member,
        'loan' => SyncChangeType.loan,
        'meeting' => SyncChangeType.meeting,
        _ => SyncChangeType.reversal,
      };

  void _setState(SyncState state) {
    _state = state;
    if (!_states.isClosed) {
      _states.add(state);
    }
  }

  void _emit(SyncEventType type, String message) {
    final SyncEvent event = SyncEvent(type, message);
    recentLog.add(event);
    if (recentLog.length > _maxLog) {
      recentLog.removeAt(0);
    }
    if (!_log.isClosed) {
      _log.add(event);
    }
  }
}
