import 'package:cryptography/cryptography.dart';

import '../crypto/member_keys.dart';
import '../crypto/sync_envelope.dart';
import '../domain/core/result.dart';
import '../domain/governance.dart';
import '../domain/group.dart';
import '../domain/invites.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import '../domain/transactions.dart';
import '../sync/ledger.dart';
import 'governance_service.dart';
import 'group_service.dart';
import 'invite_service.dart';
import 'publish_pipeline.dart';
import 'publish_tracker.dart';

/// Publishes what the sync ledger does not know yet: the outbound half
/// the UI never calls directly.
///
/// Every local write lands in the database first; each round the
/// coordinator asks the reconciler what is missing and announces the new
/// CIDs. Records applied from peers are marked by the apply pipeline, so
/// each record is published (at most) once per device — and duplicates
/// stay benign anyway, because receivers upsert by record id.
///
/// Snapshots ride the group's last-snapshot CID rather than the tracker:
/// the snapshot publisher stamps it on the group row, and applied
/// snapshots land in the ledger like any fetched block.
final class PublishReconciler {
  /// Groups for roster and writer checks.
  final GroupService groups;

  /// Live invites and governance rows for the snapshot fingerprint.
  final InviteService inviteService;

  /// Transfers, removals and dissolution for the snapshot fingerprint.
  final GovernanceService governanceService;

  /// Record listings.
  final TransactionRepository transactions;

  /// Loan listings.
  final LoanRepository loans;

  /// Meeting listings.
  final MeetingRepository meetings;

  /// Sealing, storage and ledgering.
  final PublishPipeline publish;

  /// Already-published record ids.
  final PublishTracker tracker;

  /// Ledger CIDs for snapshot staleness.
  final SyncLedger ledger;

  /// This device's X25519 pair for its own member-key announcement.
  final Future<SimpleKeyPair?> Function() memberKeyPair;

  /// This device's peer id, or null before sign-in.
  final String? Function() ownPeerId;

  /// Creates the reconciler.
  PublishReconciler({
    required this.groups,
    required this.inviteService,
    required this.governanceService,
    required this.transactions,
    required this.loans,
    required this.meetings,
    required this.publish,
    required this.tracker,
    required this.ledger,
    required this.memberKeyPair,
    required this.ownPeerId,
  });

  /// Publishes everything in [groupId] the tracker does not know, oldest
  /// records first behind a fresh snapshot. Returns the new `(cid, kind)`
  /// pairs in announce order.
  /// (Transaction reversals live with transactions; invites ride
  /// snapshots out of band.)
  Future<List<(String, String)>> publishMissing(String groupId) async {
    final List<(String, String)> fresh = [];
    final groupResult = await groups.getGroup(groupId);
    if (groupResult.isErr) {
      return fresh;
    }
    final Group group = groupResult.value;
    final String? me = ownPeerId();

    // Snapshot first: receivers need the roster before the records. A
    // snapshot goes out when the group has none, ours never landed, or
    // anything it carries changed (roster, config, invites, governance).
    final List<String> known = await ledger.cidsFor(groupId);
    final String? fingerprint = await fingerprintOf(group);
    final String? snapshotted = await tracker.snapshotFingerprint(groupId);
    if ((group.cid == null ||
            !known.contains(group.cid) ||
            (fingerprint != null && fingerprint != snapshotted)) &&
        me != null) {
      final snapshot = await publish.publishSnapshot(
        groupId: groupId,
        publisherPeerId: me,
      );
      if (snapshot.isOk) {
        if (fingerprint != null) {
          await tracker.recordSnapshotFingerprint(groupId, fingerprint);
        }
        fresh.add((snapshot.value, SyncPayloadType.groupSnapshot.name));
      }
    }

    final txResult = await transactions.listByGroup(groupId);
    if (txResult.isOk) {
      for (final Transaction tx in txResult.value) {
        if (await tracker.isPublished(groupId, tx.id)) {
          continue;
        }
        final published = await publish.publishTransaction(tx);
        if (published.isOk) {
          await tracker.markPublished(groupId, tx.id);
          fresh.add((published.value, 'tx'));
        }
      }
    }

    final reversals = await transactions.reversalsByGroup(groupId);
    if (reversals.isOk) {
      for (final reversal in reversals.value) {
        if (await tracker.isPublished(groupId, reversal.id)) {
          continue;
        }
        final published = await publish.publishReversal(reversal);
        if (published.isOk) {
          await tracker.markPublished(groupId, reversal.id);
          fresh.add((
            published.value,
            SyncPayloadType.reversal.name,
          ));
        }
      }
    }

    final loanResult = await loans.listByGroup(groupId);
    if (loanResult.isOk) {
      for (final loan in loanResult.value) {
        if (await tracker.isPublished(groupId, loan.id)) {
          continue;
        }
        final published = await publish.publishLoan(loan);
        if (published.isOk) {
          await tracker.markPublished(groupId, loan.id);
          fresh.add((published.value, SyncPayloadType.loan.name));
        }
      }
    }

    // Meetings carry the publisher's countersignature, which receivers
    // only accept from writers — so only writers republish meetings.
    var writer = false;
    if (me != null) {
      final Member? self = await groups.getMember(groupId, me);
      writer = self != null &&
          self.status == MemberStatus.active &&
          canWrite(self.role);
    }
    if (writer) {
      final meetingResult = await meetings.listByGroup(groupId);
      if (meetingResult.isOk) {
        for (final meeting in meetingResult.value) {
          if (await tracker.isPublished(groupId, meeting.id)) {
            continue;
          }
          final published = await publish.publishMeeting(meeting, me!);
          if (published.isOk) {
            await tracker.markPublished(groupId, meeting.id);
            fresh.add((
              published.value,
              SyncPayloadType.meeting.name,
            ));
          }
        }
      }
    }

    // Our own X25519 key, once: admins seal rekeyed rings to it.
    if (me != null && !await tracker.isPublished(groupId, 'memberkey:$me')) {
      final SimpleKeyPair? pair = await memberKeyPair();
      if (pair != null) {
        final published = await publish.publishMemberKey(
          groupId: groupId,
          peerId: me,
          encKey: await MemberKeys.publicKeyBytes(pair),
          keyPair: pair,
        );
        if (published.isOk) {
          await tracker.markPublished(groupId, 'memberkey:$me');
          fresh.add((
            published.value,
            SyncPayloadType.memberKey.name,
          ));
        }
      }
    }
    return fresh;
  }

  /// What the next snapshot for [group] would carry: roster sequence,
  /// live invite ids and governance counts. Null when unreadable (the
  /// caller falls back to the CID rule alone).
  Future<String?> fingerprintOf(Group group) async {
    final String groupId = group.id;
    final Result<List<Invite>> live = await inviteService.liveInvites(
      groupId,
    );
    final Result<List<OwnershipTransfer>> transfers = await governanceService
        .transfersByGroup(groupId);
    final Result<List<MemberRemoval>> removals = await governanceService
        .removalsByGroup(groupId);
    final Result<GroupDissolution?> dissolution = await governanceService
        .latestDissolution(groupId);
    if (live.isErr ||
        transfers.isErr ||
        removals.isErr ||
        dissolution.isErr) {
      return null;
    }
    final List<String> inviteIds = [
      for (final Invite i in live.value) i.id,
    ]..sort();
    return '${group.sequenceNumber}|'
        '${inviteIds.join(',')}|'
        '${transfers.value.length}|'
        '${removals.value.length}|'
        '${dissolution.value?.id ?? '-'}';
  }
}
