import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

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
import 'ipfs_service.dart';

enum SyncState { idle, syncing, error }

/// Thrown by [SyncManager.joinGroup] when the invite cannot be honoured.
class JoinGroupException implements Exception {
  final String message;
  const JoinGroupException(this.message);
  @override
  String toString() => message;
}

/// Something that arrived from a peer and changed local state. The UI layer
/// listens to refresh screens and raise local notifications.
class SyncChange {
  final SyncChangeType type;
  final String groupId;
  final String? title;
  final String? body;
  const SyncChange(this.type, this.groupId, {this.title, this.body});
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

  SyncState _state = SyncState.idle;
  DateTime? _lastSyncTime;
  Duration _syncInterval = const Duration(minutes: 5);
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
    if (_state == SyncState.syncing) return;
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
  }

  Future<void> _runSync() async {
    await _ensureNode();
    await _subscribeGroupTopics();
    await _refreshOverdueLoans();
    await _publishMissingSnapshots();
    await _syncPendingTransactions();
    await _discoverPeers();
  }

  Future<void> _ensureNode() async {
    if (!_ipfsService.isRunning) {
      await _ipfsService.start();
      _log(SyncEvent(type: SyncEventType.nodeStarted, message: 'IPFS node started'));
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

  /// DESIGN_PLAN §8: ask the DHT who else provides each group's snapshot CID
  /// and dial them, so Bitswap/PubSub have direct connections.
  Future<void> _discoverPeers() async {
    for (final g in await _groupService.getAllGroups()) {
      final cid = g.cid;
      if (cid == null) continue;
      try {
        final providers = await _ipfsService.findProviders(cid).timeout(const Duration(seconds: 10));
        for (final p in providers.take(8)) {
          try {
            await _ipfsService.connectToPeer(p);
          } catch (_) {/* best effort */}
        }
        if (providers.isNotEmpty) {
          _log(SyncEvent(
            type: SyncEventType.peersDiscovered,
            message: '${providers.length} provider(s) for ${g.name}',
          ));
        }
      } catch (_) {/* DHT lookups are best effort */}
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
    final snapshot = await _groupService.buildSnapshot(groupId, publisherPeerId: me, publisherKeyPair: kp);

    final bytes = await SyncEnvelope.seal(
      type: SyncPayloadType.groupSnapshot,
      groupId: groupId,
      plaintextJson: snapshot,
      groupKey: key,
    );
    final cid = await _ipfsService.addData(bytes);
    await _ipfsService.pin(cid);
    await _groupService.setCid(groupId, cid);
    await _announce(groupId, 'group', cid);
    _log(SyncEvent(type: SyncEventType.snapshotPublished, message: 'Group snapshot → $cid'));
    return cid;
  }

  /// Generic: seal a signed record and publish it to the group's topic.
  Future<String> publishRecord(String groupId, SyncPayloadType type, Map<String, dynamic> json) async {
    await _ensureNode();
    final key = await _groupKeyService.requireKey(groupId);
    final bytes = await SyncEnvelope.seal(type: type, groupId: groupId, plaintextJson: json, groupKey: key);
    final cid = await _ipfsService.addData(bytes);
    await _ipfsService.pin(cid);
    await _announce(groupId, type.name, cid);
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

  /// PubSub notification: only a CID and the group id (both opaque).
  Future<void> _announce(String groupId, String kind, String cid) async {
    if (!_subscribedGroups.contains(groupId)) {
      await _ipfsService.subscribe(topicFor(groupId));
      _subscribedGroups.add(groupId);
    }
    await _ipfsService.publish(
      topicFor(groupId),
      jsonEncode({'v': 1, 'kind': kind, 'groupId': groupId, 'cid': cid}),
    );
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

    try {
      await _fetchAndApply(groupId, cid);
    } catch (e) {
      _log(SyncEvent(type: SyncEventType.error, message: 'Rejected ${note['kind']} $cid: $e'));
    }
  }

  Future<void> _fetchAndApply(String groupId, String cid) async {
    final key = await _groupKeyService.getKey(groupId);
    if (key == null) return;

    final bytes = await _ipfsService.getData(cid);
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
    _changesController.add(SyncChange(
      SyncChangeType.transaction,
      groupId,
      title: 'New ${tx.type.name}',
      body: '${tx.currency} ${tx.amount.toStringAsFixed(2)}',
    ));
  }

  Future<void> _applySnapshot(Map<String, dynamic> json, String cid) async {
    final result = await _groupService.importSnapshot(json, cid: cid, ownPeerId: _ownPeerId);
    if (!result.applied) return;
    // If ownership was just handed to us, countersign and republish.
    final me = _ownPeerId;
    final kp = _ownKeyPair;
    if (me != null && kp != null) {
      final signed = await _groupService.countersignTransfer(groupId: result.group.id, ownPeerId: me, ownKeyPair: kp);
      if (signed) await publishGroupSnapshot(result.group.id);
    }
    _changesController.add(SyncChange(SyncChangeType.group, result.group.id));
  }

  static List<int> joinSigningPayload(String groupId, String peerId, String inviteId) =>
      utf8.encode('vbank:join:$groupId:$peerId:$inviteId');

  /// A new member announced themselves with an invite. Admin devices verify
  /// the invite (one-use, expiry, inviter signature), add the member, mark the
  /// invite used and republish (DESIGN_PLAN §16).
  Future<void> _applyMemberJoin(String groupId, Map<String, dynamic> json) async {
    final member = Member.fromJson(json['member'] as Map<String, dynamic>);
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
    _changesController.add(SyncChange(
      SyncChangeType.member,
      groupId,
      title: group.requireApproval ? 'Join request' : 'New member',
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
    _changesController.add(SyncChange(
      SyncChangeType.loan,
      groupId,
      title: 'Loan ${loan.status.name}',
      body: '${borrower.name}: ${loan.requestedAmount.toStringAsFixed(2)}',
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
    _changesController.add(SyncChange(
      SyncChangeType.meeting,
      groupId,
      title: 'Meeting ${meeting.status.name}',
      body: meeting.scheduledAt.toLocal().toString(),
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
    _changesController.add(SyncChange(
      SyncChangeType.reversal,
      groupId,
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
    required String passphrase,
    required Member self,
    required SimpleKeyPair keyPair,
  }) async {
    final passphraseError = GroupKeyService.validatePassphrase(passphrase);
    if (passphraseError != null) throw JoinGroupException(passphraseError);
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

    final key = await GroupKeyService.deriveKey(passphrase, groupId);

    Uint8List? bytes;
    try {
      bytes = await _ipfsService.getData(groupCid).timeout(const Duration(seconds: 45));
    } on TimeoutException {
      throw const JoinGroupException(
        'Timed out fetching the group from the network. Make sure the inviter\'s '
        'phone is online (or on the same Wi-Fi) and try again.',
      );
    }
    if (bytes == null) throw const JoinGroupException('Group data not found on the network yet');

    final envelope = SyncEnvelope.tryDecode(bytes);
    if (envelope == null || envelope.type != SyncPayloadType.groupSnapshot || envelope.groupId != groupId) {
      throw const JoinGroupException('Invite does not point at a valid group');
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
    });

    _log(SyncEvent(type: SyncEventType.memberJoined, message: 'Joined ${result.group.name}'));
    return (await _groupService.getGroup(groupId)) ?? result.group;
  }

  /// Creates a signed invite and returns the deep-link parameters
  /// (`cid`, `invite`, `n`). Owner/admin only.
  Future<InviteData> createInvite(String groupId) async {
    final me = _ownPeerId;
    final kp = _ownKeyPair;
    if (me == null || kp == null) throw StateError('Not signed in');
    await _groupService.requireWriter(groupId, me);
    final invite = await _inviteService.createInvite(
      groupId: groupId,
      groupCid: '',
      inviterPeerId: me,
      inviterKeyPair: kp,
    );
    // The snapshot must carry the invite so joiners can validate it.
    final cid = await publishGroupSnapshot(groupId);
    final withCid = InviteData(
      id: invite.id,
      groupId: invite.groupId,
      cid: cid,
      createdAt: invite.createdAt,
      expiresAt: invite.expiresAt,
      nonce: invite.nonce,
      inviterPeerId: invite.inviterPeerId,
      inviterSignature: invite.inviterSignature,
    );
    await _inviteService.upsert(withCid);
    return withCid;
  }

  // ---------------------------------------------------------------------------

  void _setState(SyncState newState) {
    _state = newState;
    _stateController.add(newState);
  }

  void _log(SyncEvent event) {
    _recentLog.insert(0, event);
    if (_recentLog.length > _maxLog) _recentLog.removeLast();
    _syncLogController.add(event);
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
