import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../crypto/member_keys.dart';
import '../crypto/signing.dart';
import '../crypto/sync_envelope.dart';
import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/governance.dart';
import '../domain/group.dart';
import '../domain/invites.dart';
import '../domain/loans.dart';
import '../domain/meetings.dart';
import '../domain/membership.dart';
import '../domain/transactions.dart';
import '../sync/record_codec.dart';
import '../sync/transport.dart';
import 'context.dart';
import 'governance_service.dart';
import 'signing_payloads.dart';
import 'group_service.dart';
import 'invite_service.dart';
import 'key_service.dart';

/// The outbound side: seal records and snapshots, store the bytes, return
/// the CID. The caller records the CID in its ledger; announcements to
/// peers and relays belong to the notification layer (phase 6).
///
/// Every payload shape matches the legacy app, so old nodes open new
/// records and vice versa.
final class PublishPipeline {
  /// P2P block storage (fake in tests).
  final SyncTransport transport;

  /// Group keys and rings.
  final GroupKeyService keys;

  /// Groups and writer checks.
  final GroupService groups;

  /// Live invites for snapshot wraps.
  final InviteService invites;

  /// Transfers, removals and dissolution for snapshot bodies.
  final GovernanceService governance;

  /// Records the published CID in the sync ledger.
  final Future<void> Function(String groupId, String cid) ledgerRecord;

  /// This device's dialable addresses for snapshot bodies.
  final List<String> Function() ownAddrs;

  /// This device's X25519 pair for rekey seals, or null to skip rekeys.
  final Future<SimpleKeyPair?> Function() memberKeyPair;

  /// Clock for snapshot timestamps.
  final AppClock clock;

  /// Creates the pipeline.
  PublishPipeline({
    required this.transport,
    required this.keys,
    required this.groups,
    required this.invites,
    required this.governance,
    required this.ledgerRecord,
    required this.ownAddrs,
    required this.memberKeyPair,
    required this.clock,
  });

  /// Seals [payloadJson] for [groupId] with the current ring key.
  Future<Uint8List> sealRecord({
    required String groupId,
    required SyncPayloadType type,
    required Map<String, dynamic> payloadJson,
    Map<String, Uint8List> wraps = const {},
    Map<String, Uint8List> rekeys = const {},
  }) async {
    final GroupKeyRing? ring = await keys.ring(groupId);
    if (ring == null) {
      throw StateError('No group key for $groupId');
    }
    return SyncEnvelope.seal(
      type: type,
      groupId: groupId,
      plaintextJson: payloadJson,
      groupKey: SecretKey(ring.current),
      keyVersion: ring.currentVersion,
      wraps: wraps,
      rekeys: rekeys,
    );
  }

  /// Seals, stores and ledgers a record; returns its CID.
  Future<Result<String>> publishRecord({
    required String groupId,
    required SyncPayloadType type,
    required Map<String, dynamic> payloadJson,
  }) async {
    try {
      final Uint8List bytes = await sealRecord(
        groupId: groupId,
        type: type,
        payloadJson: payloadJson,
      );
      final String cid = await transport.addData(bytes);
      await ledgerRecord(groupId, cid);
      return Ok(cid);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// Publishes one transaction.
  Future<Result<String>> publishTransaction(Transaction tx) =>
      publishRecord(
        groupId: tx.groupId,
        type: SyncPayloadType.transaction,
        payloadJson: RecordCodec.transactionToJson(tx),
      );

  /// Publishes an already-built payload (join announcements, member keys
  /// and other records the caller signed itself).
  Future<Result<String>> publishRaw({
    required String groupId,
    required SyncPayloadType type,
    required Map<String, dynamic> payloadJson,
  }) =>
      publishRecord(
        groupId: groupId,
        type: type,
        payloadJson: payloadJson,
      );

  /// Publishes one loan record.
  Future<Result<String>> publishLoan(LoanRequest loan) => publishRecord(
        groupId: loan.groupId,
        type: SyncPayloadType.loan,
        payloadJson: RecordCodec.loanToJson(loan),
      );

  /// Signs a meeting as the publisher and publishes it.
  Future<Result<String>> publishMeeting(
    Meeting meeting,
    String publisherPeerId,
  ) async {
    try {
      final Map<String, dynamic> meetingJson = RecordCodec.meetingToJson(
        meeting,
      );
      final Signature signature = await SigningService.sign(
        utf8.encode(jsonEncode(meetingJson)),
        await _signingKey(),
      );
      return publishRecord(
        groupId: meeting.groupId,
        type: SyncPayloadType.meeting,
        payloadJson: {
          'v': 1,
          'meeting': meetingJson,
          'publisher': publisherPeerId,
          'signature': signature.bytes,
        },
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// Publishes one reversal record.
  Future<Result<String>> publishReversal(TransactionReversal reversal) =>
      publishRecord(
        groupId: reversal.groupId,
        type: SyncPayloadType.reversal,
        payloadJson: RecordCodec.reversalToJson(reversal),
      );

  /// Publishes a member-key announcement for [peerId]'s [encKey].
  Future<Result<String>> publishMemberKey({
    required String groupId,
    required String peerId,
    required Uint8List encKey,
    required SimpleKeyPair keyPair,
  }) async {
    try {
      final Signature signature = await SigningService.sign(
        SigningPayloads.memberKey(
          groupId: groupId,
          peerId: peerId,
          encKey: encKey,
        ),
        keyPair,
      );
      return publishRecord(
        groupId: groupId,
        type: SyncPayloadType.memberKey,
        payloadJson: {
          'v': 1,
          'peerId': peerId,
          'encKey': encKey,
          'signature': signature.bytes,
        },
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// Builds the signed snapshot body (without storing): group, invites,
  /// transfers, removals, dissolution, publisher and addresses.
  Future<Result<Map<String, dynamic>>> buildSnapshot({
    required String groupId,
    required String publisherPeerId,
  }) async {
    final Result<Group> group = await groups.getGroup(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    if (groups.requireWriter(group.value, publisherPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    final Result<List<Invite>> allInvites = await invites.liveInvites(groupId);
    if (allInvites.isErr) {
      return Err(allInvites.failure);
    }
    final Result<List<OwnershipTransfer>> transfers =
        await governance.transfersByGroup(groupId);
    if (transfers.isErr) {
      return Err(transfers.failure);
    }
    final Result<List<MemberRemoval>> removals =
        await governance.removalsByGroup(groupId);
    if (removals.isErr) {
      return Err(removals.failure);
    }
    final Result<GroupDissolution?> dissolution =
        await governance.latestDissolution(groupId);
    if (dissolution.isErr) {
      return Err(dissolution.failure);
    }
    final Map<String, dynamic> body = {
      'v': 2,
      'group': RecordCodec.groupToJson(group.value),
      'invites': [
        for (final Invite i in allInvites.value)
          RecordCodec.inviteToSnapshotJson(i),
      ],
      'transfers': [
        for (final OwnershipTransfer t in transfers.value)
          RecordCodec.transferToJson(t),
      ],
      'removals': [
        for (final MemberRemoval r in removals.value)
          RecordCodec.removalToJson(r),
      ],
      'dissolution': dissolution.value == null
          ? null
          : RecordCodec.dissolutionToJson(dissolution.value!),
      'publisher': publisherPeerId,
      'publisherAddrs': ownAddrs(),
      'publishedAt': clock().toUtc().toIso8601String(),
    };
    final Signature signature = await SigningService.sign(
      utf8.encode(jsonEncode(body)),
      await _signingKey(),
    );
    return Ok({...body, 'signature': signature.bytes});
  }

  /// Publishes the snapshot: wraps live invites, rekeys after rotations,
  /// seals, stores, records the CID on the group and in the ledger.
  Future<Result<String>> publishSnapshot({
    required String groupId,
    required String publisherPeerId,
  }) async {
    try {
      final Result<Map<String, dynamic>> body = await buildSnapshot(
        groupId: groupId,
        publisherPeerId: publisherPeerId,
      );
      if (body.isErr) {
        return Err(body.failure);
      }
      final GroupKeyRing? ring = await keys.ring(groupId);
      if (ring == null) {
        return Err(NotFoundFailure('groupkey:$groupId'));
      }
      final Map<String, Uint8List> wraps = await _liveWraps(groupId);
      final Map<String, Uint8List> rekeys = await _rekeySeals(groupId, ring);
      final Uint8List bytes = await SyncEnvelope.seal(
        type: SyncPayloadType.groupSnapshot,
        groupId: groupId,
        plaintextJson: body.value,
        groupKey: SecretKey(ring.current),
        keyVersion: ring.currentVersion,
        wraps: wraps,
        rekeys: rekeys,
      );
      final String cid = await transport.addData(bytes);
      final Result<Group> group = await groups.getGroup(groupId);
      if (group.isErr) {
        return Err(group.failure);
      }
      final Result<Unit> marked = await groups.saveGroup(
        group.value.copyWith(cid: () => cid),
      );
      if (marked.isErr) {
        return Err(marked.failure);
      }
      await ledgerRecord(groupId, cid);
      return Ok(cid);
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }

  /// Rotates the group key and publishes a snapshot carrying the new ring
  /// to every remaining member. The removed member keeps old versions only.
  Future<Result<String>> rotateGroupKey({
    required String groupId,
    required String publisherPeerId,
  }) async {
    final Result<GroupKeyRing> ring = await keys.rotate(groupId);
    if (ring.isErr) {
      return Err(ring.failure);
    }
    return publishSnapshot(groupId: groupId, publisherPeerId: publisherPeerId);
  }

  /// The device identity key for meeting/snapshot signatures. Production
  /// wires the keystore key; tests pass it directly.
  Future<SimpleKeyPair> Function()? _keyForSigning;

  /// Installs the identity key source for signatures.
  void bindSigningKey(Future<SimpleKeyPair> Function() source) {
    _keyForSigning = source;
  }

  Future<SimpleKeyPair> _signingKey() async {
    final Future<SimpleKeyPair> Function()? source = _keyForSigning;
    if (source == null) {
      throw StateError('No signing key bound');
    }
    return source();
  }

  /// One wrapped ring copy per live invite (joiners unwrap with the link
  /// secret). Used and expired invites drop out: their links die.
  Future<Map<String, Uint8List>> _liveWraps(String groupId) async {
    final Result<List<Invite>> live = await invites.liveInvites(groupId);
    if (live.isErr) {
      return const {};
    }
    return {
      for (final Invite i in live.value)
        if (i.wrappedKey != null) i.id: i.wrappedKey!,
    };
  }

  /// The ring sealed for every active member holding a published key.
  /// Members without one catch up when they announce it.
  Future<Map<String, Uint8List>> _rekeySeals(
    String groupId,
    GroupKeyRing ring,
  ) async {
    if (ring.currentVersion <= 1) {
      return const {};
    }
    final SimpleKeyPair? sender = await memberKeyPair();
    final Result<Group> group = await groups.getGroup(groupId);
    if (sender == null || group.isErr) {
      return const {};
    }
    final Map<String, Uint8List> out = {};
    for (final Member m in group.value.members) {
      if (m.status != MemberStatus.active || m.encKey == null) {
        continue;
      }
      out[m.peerId] = await MemberKeys.seal(
        plaintext: ring.encode(),
        sender: sender,
        recipientPublicKey: m.encKey!,
        groupId: groupId,
        recipientPeerId: m.peerId,
      );
    }
    return out;
  }

}
