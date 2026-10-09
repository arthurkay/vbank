import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../crypto/member_keys.dart';
import '../crypto/signing.dart';
import '../crypto/sync_envelope.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/group.dart';
import '../domain/invites.dart';
import '../domain/loans.dart';
import '../domain/meetings.dart';
import '../domain/membership.dart';
import '../domain/transactions.dart';
import '../sync/engine.dart';
import '../sync/record_codec.dart';
import 'context.dart';
import 'governance_service.dart';
import 'group_service.dart';
import 'invite_service.dart';
import 'key_service.dart';
import 'loan_service.dart';
import 'meeting_service.dart';
import 'signing_payloads.dart';
import 'transaction_service.dart';

/// The engine's [BlockApplier]: envelope decode → versioned key → open →
/// dispatch by payload type with roster signature and role verification.
///
/// Outcomes: `applied` records the CID in the ledger; `rejected` parks it
/// for the session; `deferred` skips both so a later round retries once
/// the group or key version arrives. Trust rules mirror the legacy sync
/// manager exactly: only active owners/admins author records, snapshots
/// resolve newest-wins, joins never self-promote.
final class ApplyPipeline {
  /// Groups and roster checks.
  final GroupService groups;

  /// Ledger effects for transactions.
  final TransactionService transactions;

  /// Loan lifecycle effects.
  final LoanService loans;

  /// Meeting storage.
  final MeetingService meetings;

  /// Reversal verification and effects.
  final GovernanceService governance;

  /// Invite verification and used flags.
  final InviteService invites;

  /// Group keys and ring imports.
  final GroupKeyService keys;

  /// Known publisher addresses learned from snapshots and joins.
  final Future<void> Function(String groupId, Iterable<String> addrs)
      rememberAddrs;

  /// Last snapshot `publishedAt` per group (newest-wins ordering).
  final Future<DateTime?> Function(String groupId) lastPublishedAt;

  /// Records a snapshot `publishedAt` after applying.
  final Future<void> Function(String groupId, DateTime at)
      recordPublishedAt;

  /// Marks an applied record published, so the reconciler never
  /// republishes what arrived over sync. Snapshots skip this: their
  /// staleness rides the group row, not the tracker.
  final Future<void> Function(String groupId, String recordId)
      recordPublished;

  /// This device's peer id (rekey and countersign flows).
  final String ownPeerId;

  /// This device's X25519 pair for opening rekeyed rings, or null to skip
  /// rekey imports (they retry as deferred once available).
  final Future<SimpleKeyPair?> Function() memberKeyPair;

  /// Clock for invite expiry checks.
  final AppClock clock;

  /// Creates the pipeline.
  ApplyPipeline({
    required this.groups,
    required this.transactions,
    required this.loans,
    required this.meetings,
    required this.governance,
    required this.invites,
    required this.keys,
    required this.rememberAddrs,
    required this.lastPublishedAt,
    required this.recordPublishedAt,
    required this.recordPublished,
    required this.ownPeerId,
    required this.memberKeyPair,
    required this.clock,
  });

  /// Applies one fetched block for [groupId]. Never throws: every failure
  /// maps to an outcome. Anything but [ApplyOutcome.applied] logs its
  /// envelope header (type, key version), so a stuck record names itself
  /// in the sync log instead of surfacing only as round counts.
  Future<ApplyOutcome> apply(
    String groupId,
    String cid,
    Uint8List block,
  ) async {
    final SyncEnvelope? header = SyncEnvelope.tryDecode(block);
    final ApplyOutcome outcome = await _apply(groupId, cid, block);
    if (outcome != ApplyOutcome.applied) {
      final String shortCid = cid.length <= 12 ? cid : cid.substring(0, 12);
      final String type = header?.type.name ?? 'undecoded';
      final String version = header == null ? '-' : '${header.keyVersion}';
      debugPrint(
        'vBank: apply ${outcome.name} $shortCid type=$type kv=$version',
      );
    }
    return outcome;
  }

  /// The apply body: envelope decode → versioned key → open → dispatch.
  Future<ApplyOutcome> _apply(
    String groupId,
    String cid,
    Uint8List block,
  ) async {
    try {
      final SyncEnvelope? envelope = SyncEnvelope.tryDecode(block);
      if (envelope == null || envelope.groupId != groupId) {
        return ApplyOutcome.rejected;
      }
      final Result<Group> group = await groups.getGroup(groupId);
      if (group.isErr && envelope.type != SyncPayloadType.groupSnapshot) {
        // Unknown groups defer — except snapshots, which bootstrap new
        // groups through the owner trust path below.
        return ApplyOutcome.deferred;
      }
      // A snapshot may carry the key ring sealed for us: import it before
      // choosing the key so a new version opens right away.
      final Uint8List? sealedForMe = envelope.rekeys[ownPeerId];
      if (sealedForMe != null) {
        await _importRekey(groupId, sealedForMe);
      }
      final SecretKey? versionKey = await keys.keyFor(
        groupId,
        envelope.keyVersion,
      );
      if (versionKey == null) {
        return ApplyOutcome.deferred;
      }
      Map<String, dynamic> payload;
      try {
        payload = await envelope.open(versionKey);
      } on EnvelopeAuthException {
        return ApplyOutcome.rejected;
      }
      switch (envelope.type) {
        case SyncPayloadType.transaction:
          return _applyTransaction(groupId, payload);
        case SyncPayloadType.groupSnapshot:
          return _applySnapshot(payload, cid);
        case SyncPayloadType.memberJoin:
          return _applyMemberJoin(groupId, payload);
        case SyncPayloadType.loan:
          return _applyLoan(groupId, payload);
        case SyncPayloadType.meeting:
          return _applyMeeting(groupId, payload);
        case SyncPayloadType.reversal:
          return _applyReversal(groupId, payload);
        case SyncPayloadType.memberKey:
          return _applyMemberKey(groupId, payload);
      }
    } catch (_) {
      return ApplyOutcome.rejected;
    }
  }

  Future<void> _importRekey(String groupId, Uint8List sealed) async {
    final SimpleKeyPair? kp = await memberKeyPair();
    if (kp == null) {
      return;
    }
    final Uint8List? ringBytes = await MemberKeys.open(
      sealed: sealed,
      recipient: kp,
      groupId: groupId,
      recipientPeerId: ownPeerId,
    );
    final GroupKeyRing? ring =
        ringBytes == null ? null : GroupKeyRing.decode(ringBytes);
    if (ring != null) {
      // A failed import surfaces as a missing key version (deferred) at
      // the lookup below.
      await keys.importRing(groupId, ring);
    }
  }

  /// The roster member trusted to author a record: known, active,
  /// owner/admin. Null when untrusted.
  Future<Member?> _remoteWriter(String groupId, String peerId) async {
    final Member? m = await groups.getMember(groupId, peerId);
    if (m == null || m.status != MemberStatus.active) {
      return null;
    }
    if (!canWrite(m.role)) {
      return null;
    }
    return m;
  }

  Future<ApplyOutcome> _applyTransaction(
    String groupId,
    Map<String, dynamic> json,
  ) async {
    final Transaction tx = RecordCodec.transactionFromJson(json);
    if (tx.groupId != groupId) {
      return ApplyOutcome.rejected;
    }
    final Member? author = await _remoteWriter(groupId, tx.authorPeerId);
    if (author == null) {
      return ApplyOutcome.rejected;
    }
    final Result<ImportResult> outcome = await transactions.importRemote(
      tx,
      authorPublicKey: author.publicKey,
    );
    if (outcome.isErr) {
      return ApplyOutcome.rejected;
    }
    if (outcome.value == ImportResult.imported &&
        tx.type == TransactionType.repayment &&
        tx.loanId != null) {
      await loans.applyRemoteRepayment(tx.loanId!, tx.amount);
    }
    await recordPublished(groupId, tx.id);
    return ApplyOutcome.applied;
  }

  Future<ApplyOutcome> _applySnapshot(
    Map<String, dynamic> json,
    String cid,
  ) async {
    final Map<String, dynamic>? groupJson =
        json['group'] as Map<String, dynamic>?;
    final Group incoming;
    try {
      if (groupJson == null) {
        return ApplyOutcome.rejected;
      }
      incoming = RecordCodec.groupFromJson(groupJson);
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    final String? publisher = json['publisher'] as String?;
    final List<int>? signature = (json['signature'] as List?)?.cast<int>();
    final DateTime? publishedAt =
        DateTime.tryParse(json['publishedAt'] as String? ?? '')?.toUtc();
    if (publisher == null || signature == null || publishedAt == null) {
      return ApplyOutcome.rejected;
    }
    final List<String> addrs =
        ((json['publisherAddrs'] as List?) ?? const []).cast<String>();
    if (addrs.isNotEmpty) {
      await rememberAddrs(incoming.id, addrs);
    }

    // Who signed, and may they? Known groups: an active owner/admin of our
    // roster. New groups: the owner named inside, with a valid owner seal.
    final Result<Group> existing = await groups.getGroup(incoming.id);
    Uint8List publisherKey;
    if (existing.isOk) {
      final Member? local = await groups.getMember(incoming.id, publisher);
      if (local == null ||
          local.status != MemberStatus.active ||
          !canWrite(local.role)) {
        return ApplyOutcome.rejected;
      }
      publisherKey = local.publicKey;
    } else {
      final Member? owner = incoming.owner;
      if (owner == null || owner.peerId != publisher) {
        return ApplyOutcome.rejected;
      }
      final bool ownerOk = await SigningService.verifyWithBytes(
        SigningPayloads.groupOwner(incoming.id, owner.peerId),
        incoming.ownerSignature,
        owner.publicKey,
      );
      if (!ownerOk) {
        return ApplyOutcome.rejected;
      }
      publisherKey = owner.publicKey;
    }
    final Map<String, dynamic> body = Map<String, dynamic>.from(json)
      ..remove('signature');
    final bool sigOk = await SigningService.verifyWithBytes(
      utf8.encode(jsonEncode(body)),
      signature,
      publisherKey,
    );
    if (!sigOk) {
      return ApplyOutcome.rejected;
    }

    // Newest wins: sequence, then published time, then publisher id.
    if (existing.isOk) {
      final DateTime localAt =
          (await lastPublishedAt(incoming.id)) ?? existing.value.createdAt;
      final bool newer = incoming.sequenceNumber >
              existing.value.sequenceNumber ||
          (incoming.sequenceNumber == existing.value.sequenceNumber &&
              publishedAt.isAfter(localAt)) ||
          (incoming.sequenceNumber == existing.value.sequenceNumber &&
              publishedAt.isAtSameMomentAs(localAt) &&
              publisher.compareTo(ownPeerId) > 0);
      await invites.mergeUsed(_snapshotInvites(json));
      if (!newer) {
        await _recordSnapshotCid(incoming.id, cid);
        return ApplyOutcome.applied;
      }
    }

    final Result<Unit> stored = await _storeSnapshot(incoming, json, cid);
    if (stored.isErr) {
      return ApplyOutcome.rejected;
    }
    await recordPublishedAt(incoming.id, publishedAt);
    // Ownership handed to us: countersign so the roster settles. The
    // coordinator republishes afterwards.
    await groups.countersignTransfer(
      group: (await groups.getGroup(incoming.id)).value,
      ownPeerId: ownPeerId,
    );
    return ApplyOutcome.applied;
  }

  /// Persists a snapshot body: group row, authoritative roster, invite
  /// flags, transfers, removals and dissolution. Snapshots carry history,
  /// never deletions: rows upsert by id.
  Future<Result<Unit>> _storeSnapshot(
    Group incoming,
    Map<String, dynamic> json,
    String cid,
  ) async {
    final Result<Unit> saved = await groups.saveGroup(
      incoming.copyWith(cid: () => cid),
    );
    if (saved.isErr) {
      return saved;
    }
    final Result<Unit> merged = await invites.mergeUsed(
      _snapshotInvites(json),
    );
    if (merged.isErr) {
      return merged;
    }
    try {
      for (final Object? t in (json['transfers'] as List?) ?? const []) {
        final Result<Unit> stored = await governance.saveTransfer(
          RecordCodec.transferFromJson((t as Map).cast<String, dynamic>()),
        );
        if (stored.isErr) {
          return stored;
        }
      }
      for (final Object? r in (json['removals'] as List?) ?? const []) {
        final Result<Unit> stored = await governance.saveRemoval(
          RecordCodec.removalFromJson((r as Map).cast<String, dynamic>()),
        );
        if (stored.isErr) {
          return stored;
        }
      }
      final Map<String, dynamic>? dissolution =
          json['dissolution'] as Map<String, dynamic>?;
      if (dissolution != null) {
        final Result<Unit> stored = await governance.saveDissolution(
          RecordCodec.dissolutionFromJson(dissolution),
        );
        if (stored.isErr) {
          return stored;
        }
      }
    } catch (_) {
      return const Err(ValidationFailure('snapshot.governance'));
    }
    return const Ok(unit);
  }

  /// Snapshot invite rows from the body.
  List<Invite> _snapshotInvites(Map<String, dynamic> json) {
    final List<Invite> out = [];
    for (final Object? j in (json['invites'] as List?) ?? const []) {
      try {
        out.add(
          RecordCodec.inviteFromSnapshotJson(
            (j as Map).cast<String, dynamic>(),
          ),
        );
      } catch (_) {
        // One bad invite row must not sink the snapshot.
      }
    }
    return out;
  }

  /// Records the snapshot CID without touching anything else.
  Future<void> _recordSnapshotCid(String groupId, String cid) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isOk) {
      await groups.saveGroup(group.value.copyWith(cid: () => cid));
    }
  }

  Future<ApplyOutcome> _applyMemberJoin(
    String groupId,
    Map<String, dynamic> json,
  ) async {
    Member member;
    try {
      member = RecordCodec.memberFromJson(
        (json['member'] as Map).cast<String, dynamic>(),
      );
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    final List<String> joinerAddrs =
        ((json['addrs'] as List?) ?? const []).cast<String>();
    if (joinerAddrs.isNotEmpty) {
      await rememberAddrs(groupId, joinerAddrs);
    }
    List<int>? signature;
    try {
      signature = (json['signature'] as List).cast<int>();
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    final String? inviteId = json['inviteId'] as String?;
    final String? nonceB64 = json['nonce'] as String?;
    if (inviteId == null || nonceB64 == null) {
      return ApplyOutcome.rejected;
    }
    final bool sigOk = await SigningService.verifyWithBytes(
      SigningPayloads.memberJoin(
        groupId: groupId,
        peerId: member.peerId,
        inviteId: inviteId,
      ),
      signature,
      member.publicKey,
    );
    if (!sigOk) {
      return ApplyOutcome.rejected;
    }
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return ApplyOutcome.rejected;
    }
    Member? me;
    for (final Member m in group.value.members) {
      if (m.peerId == ownPeerId) {
        me = m;
      }
    }
    // Only admins act on joins; the rest converge through snapshots.
    if (me == null ||
        me.status != MemberStatus.active ||
        !canManageMembers(me.role)) {
      return ApplyOutcome.applied;
    }
    final Result<bool> banned = await groups.isBanned(
      groupId,
      member.peerId,
    );
    if (banned.isErr) {
      return ApplyOutcome.rejected;
    }
    if (banned.value) {
      // A removed member found a fresh link: spend the invite, keep them
      // out. The owner can allow them back.
      await invites.markUsed(inviteId);
      return ApplyOutcome.applied;
    }
    final Result<Invite> invite = await invites.getById(inviteId);
    if (invite.isErr) {
      return ApplyOutcome.rejected;
    }
    final Member? inviter = await groups.getMember(
      groupId,
      invite.value.inviterPeerId,
    );
    if (inviter == null || !canWrite(inviter.role)) {
      return ApplyOutcome.rejected;
    }
    final Result<Unit> verified = await InviteService.verify(
      invite.value,
      groupId: groupId,
      presentedNonce: base64Decode(nonceB64),
      inviterPublicKey: inviter.publicKey,
      now: clock(),
    );
    if (verified.isErr) {
      return ApplyOutcome.rejected;
    }
    final Member? existing = await groups.getMember(groupId, member.peerId);
    if (existing == null) {
      final Result<Unit> added = await groups.addMember(
        group.value,
        Member(
          peerId: member.peerId,
          name: member.name,
          role: MemberRole.member,
          joinedAt: member.joinedAt,
          publicKey: member.publicKey,
          status: group.value.requireApproval
              ? MemberStatus.pending
              : MemberStatus.active,
          encKey: member.encKey,
        ),
      );
      if (added.isErr) {
        return ApplyOutcome.rejected;
      }
    } else if (member.encKey != null && existing.encKey == null) {
      final Result<Unit> keyed = await groups.setMemberEncKey(
        group.value,
        member.peerId,
        member.encKey!,
      );
      if (keyed.isErr) {
        return ApplyOutcome.rejected;
      }
    }
    await invites.markUsed(inviteId);
    return ApplyOutcome.applied;
  }

  Future<ApplyOutcome> _applyLoan(
    String groupId,
    Map<String, dynamic> json,
  ) async {
    LoanRequest loan;
    try {
      loan = RecordCodec.loanFromJson(json);
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    if (loan.groupId != groupId) {
      return ApplyOutcome.rejected;
    }
    final Member? borrower = await groups.getMember(
      groupId,
      loan.borrowerPeerId,
    );
    if (borrower == null) {
      return ApplyOutcome.rejected;
    }
    if (!await loans.verifyRequestSignature(
      loan,
      borrower.publicKey,
    )) {
      return ApplyOutcome.rejected;
    }
    if (loan.status != LoanStatus.pending) {
      final String? approverId = loan.approvedByPeerId;
      if (approverId == null) {
        return ApplyOutcome.rejected;
      }
      Member? approver;
      if (approverId == loan.borrowerPeerId) {
        // Self-approved loans (approval-free groups).
        approver = borrower;
      } else {
        approver = await _remoteWriter(groupId, approverId);
      }
      if (approver == null) {
        return ApplyOutcome.rejected;
      }
      if (!await loans.verifyApprovalSignature(loan, approver.publicKey)) {
        return ApplyOutcome.rejected;
      }
    }
    final Result<Unit> stored = await loans.importRemote(loan);
    if (stored.isErr) {
      return ApplyOutcome.rejected;
    }
    await recordPublished(groupId, loan.id);
    return ApplyOutcome.applied;
  }

  Future<ApplyOutcome> _applyMeeting(
    String groupId,
    Map<String, dynamic> json,
  ) async {
    final String? publisher = json['publisher'] as String?;
    List<int>? signature;
    Map<String, dynamic>? meetingJson;
    try {
      signature = (json['signature'] as List).cast<int>();
      meetingJson = (json['meeting'] as Map).cast<String, dynamic>();
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    if (publisher == null) {
      return ApplyOutcome.rejected;
    }
    final Member? author = await _remoteWriter(groupId, publisher);
    if (author == null) {
      return ApplyOutcome.rejected;
    }
    final bool ok = await SigningService.verifyWithBytes(
      utf8.encode(jsonEncode(meetingJson)),
      signature,
      author.publicKey,
    );
    if (!ok) {
      return ApplyOutcome.rejected;
    }
    Meeting meeting;
    try {
      meeting = RecordCodec.meetingFromJson(meetingJson);
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    if (meeting.groupId != groupId) {
      return ApplyOutcome.rejected;
    }
    final Result<Unit> stored = await meetings.importRemote(meeting);
    if (stored.isErr) {
      return ApplyOutcome.rejected;
    }
    await recordPublished(groupId, meeting.id);
    return ApplyOutcome.applied;
  }

  Future<ApplyOutcome> _applyReversal(
    String groupId,
    Map<String, dynamic> json,
  ) async {
    TransactionReversal reversal;
    try {
      reversal = RecordCodec.reversalFromJson(json);
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    if (reversal.groupId != groupId) {
      return ApplyOutcome.rejected;
    }
    final Result<Unit> stored = await governance.importRemote(reversal);
    if (stored.isErr) {
      return ApplyOutcome.rejected;
    }
    await recordPublished(groupId, reversal.id);
    return ApplyOutcome.applied;
  }

  Future<ApplyOutcome> _applyMemberKey(
    String groupId,
    Map<String, dynamic> json,
  ) async {
    final String? peerId = json['peerId'] as String?;
    List<int>? encKey;
    List<int>? signature;
    try {
      encKey = (json['encKey'] as List).cast<int>();
      signature = (json['signature'] as List).cast<int>();
    } catch (_) {
      return ApplyOutcome.rejected;
    }
    if (peerId == null) {
      return ApplyOutcome.rejected;
    }
    final Member? member = await groups.getMember(groupId, peerId);
    if (member == null) {
      // The roster hasn't caught up (join/snapshot still in flight):
      // retry once it arrives instead of parking for the session.
      return ApplyOutcome.deferred;
    }
    final bool ok = await SigningService.verifyWithBytes(
      SigningPayloads.memberKey(
        groupId: groupId,
        peerId: peerId,
        encKey: encKey,
      ),
      signature,
      member.publicKey,
    );
    if (!ok) {
      return ApplyOutcome.rejected;
    }
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return ApplyOutcome.rejected;
    }
    final Result<Unit> stored = await groups.setMemberEncKey(
      group.value,
      peerId,
      Uint8List.fromList(encKey),
    );
    if (stored.isErr) {
      return ApplyOutcome.rejected;
    }
    await recordPublished(groupId, 'memberkey:$peerId');
    return ApplyOutcome.applied;
  }
}
