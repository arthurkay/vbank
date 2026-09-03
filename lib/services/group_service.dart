import 'dart:convert';
import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import '../core/crypto/signing.dart';
import '../core/storage/balance_dao.dart';
import '../core/storage/governance_dao.dart';
import '../core/storage/group_dao.dart';
import '../core/storage/loan_dao.dart';
import '../core/storage/member_dao.dart';
import '../models/group.dart';
import '../models/group_dissolution.dart';
import '../models/loan.dart';
import '../models/member_removal.dart';
import '../models/ownership_transfer.dart';
import 'group_key_service.dart';
import 'invite_service.dart';
import 'transaction_service.dart' show PermissionException;

/// Result of applying a peer's snapshot.
class SnapshotImportResult {
  final Group group;
  final bool applied;
  final String reason;
  const SnapshotImportResult(this.group, this.applied, this.reason);
}

class GroupService {
  final GroupDao _groupDao;
  final MemberDao _memberDao;
  final BalanceDao _balanceDao;
  final LoanDao _loanDao;
  final GovernanceDao _governanceDao;
  final InviteService _inviteService;
  final GroupKeyService _groupKeyService;
  static const _uuid = Uuid();

  GroupService({
    GroupKeyService? groupKeyService,
    InviteService? inviteService,
    GroupDao? groupDao,
    MemberDao? memberDao,
    BalanceDao? balanceDao,
    LoanDao? loanDao,
    GovernanceDao? governanceDao,
  })  : _groupKeyService = groupKeyService ?? GroupKeyService(),
        _inviteService = inviteService ?? InviteService(),
        _groupDao = groupDao ?? GroupDao(),
        _memberDao = memberDao ?? MemberDao(),
        _balanceDao = balanceDao ?? BalanceDao(),
        _loanDao = loanDao ?? LoanDao(),
        _governanceDao = governanceDao ?? GovernanceDao();

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------

  static Uint8List _encodeConfig(GroupConfig config) =>
      Uint8List.fromList(utf8.encode(jsonEncode(config.toJson())));

  static GroupConfig _decodeConfig(Uint8List bytes, String groupId) {
    if (bytes.isEmpty) return GroupConfig(groupId: groupId, contributionAmount: 0);
    final json = jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    return GroupConfig.fromJson({...json, 'groupId': groupId});
  }

  static T _enumByName<T extends Enum>(List<T> values, String? name, T fallback) =>
      values.firstWhere((v) => v.name == name, orElse: () => fallback);

  static List<int> ownerSigningPayload(String groupId, String ownerPeerId) =>
      utf8.encode('$groupId:$ownerPeerId');

  Member _memberFromData(MemberData m) => Member(
        peerId: m.peerId,
        name: m.name,
        role: _enumByName(MemberRole.values, m.role, MemberRole.member),
        joinedAt: m.joinedAt,
        publicKey: m.publicKey,
        status: _enumByName(MemberStatus.values, m.status, MemberStatus.active),
        hasOutstandingLoan: m.hasOutstandingLoan,
      );

  MemberData _memberToData(String groupId, Member m) => MemberData(
        peerId: m.peerId,
        groupId: groupId,
        name: m.name,
        role: m.role.name,
        status: m.status.name,
        publicKey: m.publicKey,
        joinedAt: m.joinedAt,
        hasOutstandingLoan: m.hasOutstandingLoan,
      );

  // --- permissions (DESIGN_PLAN §13) -----------------------------------------

  bool canWrite(MemberRole role) => role == MemberRole.owner || role == MemberRole.admin;
  bool canManageMembers(MemberRole role) => role == MemberRole.owner || role == MemberRole.admin;
  bool canPromote(MemberRole role) => role == MemberRole.owner;
  bool canDemote(MemberRole role) => role == MemberRole.owner;
  bool canRemove(MemberRole role) => role == MemberRole.owner;
  bool canDissolve(MemberRole role) => role == MemberRole.owner;
  bool canTransferOwnership(MemberRole role) => role == MemberRole.owner;

  /// The acting member, or throws if not an active member.
  Future<Member> requireActiveMember(String groupId, String peerId) async {
    final m = await _memberDao.get(peerId, groupId);
    if (m == null) throw const PermissionException('You are not a member of this group');
    if (m.status != MemberStatus.active.name) {
      throw const PermissionException('Your membership is not active');
    }
    return _memberFromData(m);
  }

  Future<Member> requireRole(
    String groupId,
    String peerId,
    bool Function(MemberRole) allowed,
    String denied,
  ) async {
    final m = await requireActiveMember(groupId, peerId);
    if (!allowed(m.role)) throw PermissionException(denied);
    return m;
  }

  Future<Member> requireWriter(String groupId, String peerId) => requireRole(
        groupId, peerId, canWrite, 'Only the group owner or an admin can do this');

  Future<Member> requireOwner(String groupId, String peerId) => requireRole(
        groupId, peerId, (r) => r == MemberRole.owner, 'Only the group owner can do this');

  Future<void> _requireActiveGroup(String groupId) async {
    final g = await _groupDao.getById(groupId);
    if (g == null) throw StateError('Group $groupId not found');
    if (g.status == GroupStatus.dissolved.name) {
      throw const PermissionException('This group has been dissolved');
    }
  }

  /// Every local metadata mutation bumps the sequence number (§19).
  Future<void> _touch(String groupId) => _groupDao.bumpSequence(groupId);

  // ---------------------------------------------------------------------------
  // Create / read
  // ---------------------------------------------------------------------------

  /// Creates a group. [passphrase] is the shared group secret (DESIGN_PLAN
  /// §12): the group key is derived from it and stored locally; the
  /// passphrase itself is never persisted.
  Future<Group> createGroup({
    required String name,
    required GroupConfig config,
    /// Legacy: derive the group key from a shared passphrase. Null (the
    /// default for new groups) generates a random key that reaches members
    /// through invite links.
    String? passphrase,
    required String ownerPeerId,
    required String ownerName,
    required Uint8List ownerPublicKey,
    required SimpleKeyPair ownerKeyPair,
    bool requireApproval = false,
  }) async {
    if (ownerPeerId.isEmpty || ownerName.isEmpty || ownerPublicKey.isEmpty) {
      throw ArgumentError('Group owner identity is incomplete');
    }
    if (passphrase != null) {
      final passphraseError = GroupKeyService.validatePassphrase(passphrase);
      if (passphraseError != null) throw ArgumentError(passphraseError);
    }
    if (config.contributionAmount <= 0) {
      throw ArgumentError('Contribution amount must be positive');
    }

    final groupId = _uuid.v4();
    final signatureBytes = await SigningService.sign(
      ownerSigningPayload(groupId, ownerPeerId),
      ownerKeyPair,
    );
    final ownerSignature = Uint8List.fromList(signatureBytes.bytes);
    final now = DateTime.now().toUtc();

    final owner = Member(
      peerId: ownerPeerId,
      name: ownerName,
      role: MemberRole.owner,
      joinedAt: now,
      publicKey: ownerPublicKey,
    );

    final fullConfig = GroupConfig.fromJson({...config.toJson(), 'groupId': groupId});

    await _groupDao.insert(GroupData(
      id: groupId,
      name: name,
      data: ownerSignature,
      configData: _encodeConfig(fullConfig),
      requireApproval: requireApproval,
      createdAt: now,
      updatedAt: now,
    ));
    await _memberDao.insert(_memberToData(groupId, owner));
    await _balanceDao.ensureExists(owner.peerId, groupId);
    if (passphrase == null) {
      await _groupKeyService.setRandom(groupId);
    } else {
      await _groupKeyService.setFromPassphrase(groupId, passphrase);
    }

    return (await getGroup(groupId))!;
  }

  Future<Group?> getGroup(String groupId) async {
    final groupData = await _groupDao.getById(groupId);
    if (groupData == null) return null;
    final members = await _memberDao.getByGroupId(groupId);
    return Group(
      id: groupData.id,
      name: groupData.name,
      config: _decodeConfig(groupData.configData, groupData.id),
      members: members.map(_memberFromData).toList(),
      requireApproval: groupData.requireApproval,
      createdAt: groupData.createdAt,
      sequenceNumber: groupData.sequenceNumber,
      status: _enumByName(GroupStatus.values, groupData.status, GroupStatus.active),
      ownerSignature: groupData.data,
      cid: groupData.cid,
    );
  }

  Future<List<Group>> getAllGroups() async {
    final groups = await _groupDao.getAll();
    final result = <Group>[];
    for (final g in groups) {
      final group = await getGroup(g.id);
      if (group != null) result.add(group);
    }
    return result;
  }

  Future<Member?> getMember(String groupId, String peerId) async {
    final m = await _memberDao.get(peerId, groupId);
    return m == null ? null : _memberFromData(m);
  }

  // ---------------------------------------------------------------------------
  // Membership (DESIGN_PLAN §13)
  // ---------------------------------------------------------------------------

  /// Low-level upsert used by joins, snapshots and restores. Not permission
  /// checked — callers are the sync layer or an already-authorised action.
  Future<void> addMember({
    required String groupId,
    required Member member,
    bool bumpSequence = true,
  }) async {
    await _memberDao.upsert(_memberToData(groupId, member));
    await _balanceDao.ensureExists(member.peerId, groupId);
    if (bumpSequence) await _touch(groupId);
  }

  /// Admin approves a `pending` member (groups with requireApproval).
  Future<void> approveMember({
    required String groupId,
    required String actingPeerId,
    required String peerId,
  }) async {
    await _requireActiveGroup(groupId);
    await requireRole(groupId, actingPeerId, canManageMembers, 'Only the owner or an admin can approve members');
    final target = await _memberDao.get(peerId, groupId);
    if (target == null) throw StateError('Member not found');
    if (target.status != MemberStatus.pending.name) return;
    await _memberDao.updateStatus(peerId, groupId, MemberStatus.active.name);
    await _touch(groupId);
  }

  Future<void> rejectMember({
    required String groupId,
    required String actingPeerId,
    required String peerId,
  }) async {
    await requireRole(groupId, actingPeerId, canManageMembers, 'Only the owner or an admin can reject members');
    final target = await _memberDao.get(peerId, groupId);
    if (target == null || target.status != MemberStatus.pending.name) return;
    await _memberDao.delete(peerId, groupId);
    await _touch(groupId);
  }

  /// Owner promotes member→admin or demotes admin→member. The owner role is
  /// only changed via [transferOwnership].
  /// Changes the name a member is known by in every group they belong to.
  /// The change rides along with the next group snapshot like any other
  /// membership edit.
  Future<void> renameMember({required String peerId, required String name}) async {
    for (final g in await getAllGroups()) {
      final m = await _memberDao.get(peerId, g.id);
      if (m == null || m.name == name) continue;
      await _memberDao.updateName(peerId, g.id, name);
      await _touch(g.id);
    }
  }

  Future<void> updateMemberRole({
    required String groupId,
    required String actingPeerId,
    required String peerId,
    required MemberRole newRole,
  }) async {
    await _requireActiveGroup(groupId);
    final acting = await requireOwner(groupId, actingPeerId);
    final target = await _memberDao.get(peerId, groupId);
    if (target == null) throw StateError('Member not found');
    if (newRole == MemberRole.owner || target.role == MemberRole.owner.name) {
      throw const PermissionException('Use "Transfer ownership" to change the owner');
    }
    if (target.role == newRole.name) return;
    final promoting = newRole == MemberRole.admin;
    if (promoting && !canPromote(acting.role)) throw const PermissionException('Only the owner can promote');
    if (!promoting && !canDemote(acting.role)) throw const PermissionException('Only the owner can demote');
    await _memberDao.updateRole(peerId, groupId, newRole.name);
    await _touch(groupId);
  }

  /// Suspend / reinstate. Admins may act on members; only the owner may act
  /// on admins; nobody may suspend the owner.
  Future<void> updateMemberStatus({
    required String groupId,
    required String actingPeerId,
    required String peerId,
    required MemberStatus newStatus,
  }) async {
    await _requireActiveGroup(groupId);
    final acting = await requireRole(groupId, actingPeerId, canManageMembers, 'Only the owner or an admin can do this');
    final target = await _memberDao.get(peerId, groupId);
    if (target == null) throw StateError('Member not found');
    if (target.role == MemberRole.owner.name) {
      throw const PermissionException('The group owner cannot be suspended');
    }
    if (target.role == MemberRole.admin.name && acting.role != MemberRole.owner) {
      throw const PermissionException('Only the owner can change an admin\'s status');
    }
    if (newStatus == MemberStatus.removed) {
      throw ArgumentError('Use removeMember to remove a member');
    }
    await _memberDao.updateStatus(peerId, groupId, newStatus.name);
    await _touch(groupId);
  }

  /// Owner removes a member (DESIGN_PLAN §13/§35 "removal with loan
  /// settlement"). If the member has an active loan the caller must pass
  /// [settleOutstandingLoan] = true, which marks the loan defaulted and records
  /// the outstanding amount in the removal record.
  Future<MemberRemoval> removeMember({
    required String groupId,
    required String actingPeerId,
    required SimpleKeyPair actingKeyPair,
    required String peerId,
    required String reason,
    bool settleOutstandingLoan = false,
  }) async {
    await _requireActiveGroup(groupId);
    await requireRole(groupId, actingPeerId, canRemove, 'Only the group owner can remove members');
    final target = await _memberDao.get(peerId, groupId);
    if (target == null) throw StateError('Member not found');
    if (target.role == MemberRole.owner.name) {
      throw const PermissionException('The group owner cannot be removed');
    }

    final activeLoans = (await _loanDao.getByGroupId(groupId))
        .where((l) => l.borrowerPeerId == peerId &&
            (l.status == LoanStatus.disbursed.name || l.status == LoanStatus.repaying.name))
        .toList();
    final outstanding = activeLoans.fold<double>(0, (s, l) => s + (l.approvedAmount ?? 0));
    if (activeLoans.isNotEmpty && !settleOutstandingLoan) {
      throw const PermissionException(
        'Member has an outstanding loan. Settle it first or choose "remove and write off".',
      );
    }
    for (final l in activeLoans) {
      await _loanDao.updateStatus(l.id, LoanStatus.defaulted.name);
    }

    final removedAt = DateTime.now().toUtc();
    final removalId = _uuid.v4();
    final action = activeLoans.isNotEmpty ? RemovalAction.settleAndRemove : RemovalAction.remove;
    final signature = await SigningService.sign(
      utf8.encode('vbank:remove:$removalId:$groupId:$peerId:${action.name}'),
      actingKeyPair,
    );
    final removal = MemberRemoval(
      id: removalId,
      groupId: groupId,
      removedPeerId: peerId,
      removedByPeerId: actingPeerId,
      reason: reason,
      hasOutstandingLoan: activeLoans.isNotEmpty,
      outstandingAmount: outstanding,
      action: action,
      removedAt: removedAt,
      adminSignature: Uint8List.fromList(signature.bytes),
    );
    await _governanceDao.insertRemoval(removal);
    // Keep the row (status = removed) so the ledger still resolves the peer.
    await _memberDao.updateStatus(peerId, groupId, MemberStatus.removed.name);
    await _touch(groupId);
    return removal;
  }

  Future<List<MemberRemoval>> removals(String groupId) => _governanceDao.removalsForGroup(groupId);

  // ---------------------------------------------------------------------------
  // Config
  // ---------------------------------------------------------------------------

  Future<void> updateGroupConfig({
    required String groupId,
    required String actingPeerId,
    required GroupConfig config,
    bool? requireApproval,
  }) async {
    await _requireActiveGroup(groupId);
    await requireWriter(groupId, actingPeerId);
    final group = await _groupDao.getById(groupId);
    if (group == null) return;
    if (config.contributionAmount <= 0) throw ArgumentError('Contribution amount must be positive');

    await _groupDao.update(GroupData(
      id: group.id,
      name: group.name,
      data: group.data,
      configData: _encodeConfig(GroupConfig.fromJson({...config.toJson(), 'groupId': groupId})),
      cid: group.cid,
      requireApproval: requireApproval ?? group.requireApproval,
      status: group.status,
      createdAt: group.createdAt,
      sequenceNumber: group.sequenceNumber,
      updatedAt: group.updatedAt,
    ));
    await _touch(groupId);
  }

  Future<void> renameGroup({
    required String groupId,
    required String actingPeerId,
    required String name,
  }) async {
    await requireWriter(groupId, actingPeerId);
    final group = await _groupDao.getById(groupId);
    if (group == null) return;
    if (name.trim().isEmpty) throw ArgumentError('Name cannot be empty');
    await _groupDao.update(GroupData(
      id: group.id,
      name: name.trim(),
      data: group.data,
      configData: group.configData,
      cid: group.cid,
      requireApproval: group.requireApproval,
      status: group.status,
      createdAt: group.createdAt,
      sequenceNumber: group.sequenceNumber,
      updatedAt: group.updatedAt,
    ));
    await _touch(groupId);
  }

  /// Records the CID of the latest published (encrypted) snapshot.
  Future<void> setCid(String groupId, String cid) => _groupDao.updateSyncStatus(groupId, cid);

  // ---------------------------------------------------------------------------
  // Ownership transfer (DESIGN_PLAN §17)
  // ---------------------------------------------------------------------------

  static List<int> transferSigningPayload(String transferId, String groupId, String from, String to) =>
      utf8.encode('vbank:transfer:$transferId:$groupId:$from:$to');

  /// The owner hands the group to an active admin. The old owner's signature
  /// is recorded now; the new owner's device countersigns when it applies the
  /// snapshot (see [countersignTransfer]).
  Future<OwnershipTransfer> transferOwnership({
    required String groupId,
    required String actingPeerId,
    required SimpleKeyPair actingKeyPair,
    required String toPeerId,
  }) async {
    await _requireActiveGroup(groupId);
    await requireRole(groupId, actingPeerId, canTransferOwnership, 'Only the owner can transfer ownership');
    final target = await _memberDao.get(toPeerId, groupId);
    if (target == null) throw StateError('Member not found');
    if (target.status != MemberStatus.active.name || target.role != MemberRole.admin.name) {
      throw const PermissionException('Ownership can only be transferred to an active admin');
    }

    final id = _uuid.v4();
    final sig = await SigningService.sign(
      transferSigningPayload(id, groupId, actingPeerId, toPeerId),
      actingKeyPair,
    );
    final transfer = OwnershipTransfer(
      id: id,
      groupId: groupId,
      fromPeerId: actingPeerId,
      toPeerId: toPeerId,
      transferredAt: DateTime.now().toUtc(),
      oldOwnerSignature: Uint8List.fromList(sig.bytes),
      newOwnerSignature: Uint8List(0),
    );
    await _governanceDao.upsertTransfer(transfer);
    await _memberDao.updateRole(actingPeerId, groupId, MemberRole.admin.name);
    await _memberDao.updateRole(toPeerId, groupId, MemberRole.owner.name);
    await _touch(groupId);
    return transfer;
  }

  /// Called on the new owner's device once the transfer has arrived.
  Future<bool> countersignTransfer({
    required String groupId,
    required String ownPeerId,
    required SimpleKeyPair ownKeyPair,
  }) async {
    final pending = (await _governanceDao.transfersForGroup(groupId))
        .where((t) => t.toPeerId == ownPeerId && t.newOwnerSignature.isEmpty)
        .toList();
    if (pending.isEmpty) return false;
    for (final t in pending) {
      final sig = await SigningService.sign(
        transferSigningPayload(t.id, groupId, t.fromPeerId, t.toPeerId),
        ownKeyPair,
      );
      await _governanceDao.upsertTransfer(OwnershipTransfer(
        id: t.id,
        groupId: t.groupId,
        fromPeerId: t.fromPeerId,
        toPeerId: t.toPeerId,
        transferredAt: t.transferredAt,
        oldOwnerSignature: t.oldOwnerSignature,
        newOwnerSignature: Uint8List.fromList(sig.bytes),
      ));
    }
    await _touch(groupId);
    return true;
  }

  Future<List<OwnershipTransfer>> transfers(String groupId) => _governanceDao.transfersForGroup(groupId);

  // ---------------------------------------------------------------------------
  // Dissolution state (DESIGN_PLAN §18) — the money movements live in
  // GovernanceService; this only persists status.
  // ---------------------------------------------------------------------------

  Future<GroupDissolution?> dissolution(String groupId) => _governanceDao.latestDissolution(groupId);

  Future<void> saveDissolution(GroupDissolution d) async {
    await _governanceDao.upsertDissolution(d);
    if (d.status == DissolutionStatus.completed) {
      await _groupDao.updateStatus(d.groupId, GroupStatus.dissolved.name);
    }
    await _touch(d.groupId);
  }

  // ---------------------------------------------------------------------------
  // Snapshots — the group's metadata as shared over IPFS, always inside an
  // encrypted SyncEnvelope (see SyncManager) and signed by an owner/admin.
  // ---------------------------------------------------------------------------

  static const snapshotVersion = 2;

  static List<int> snapshotSigningBytes(Map<String, dynamic> body) =>
      utf8.encode(jsonEncode(body));

  /// Serialises group + members + invites + governance records and signs the
  /// whole thing with [publisherKeyPair]. The publisher must be an owner/admin.
  Future<Map<String, dynamic>> buildSnapshot(
    String groupId, {
    required String publisherPeerId,
    required SimpleKeyPair publisherKeyPair,
    List<String> publisherAddrs = const [],
  }) async {
    final group = await getGroup(groupId);
    if (group == null) throw StateError('Group $groupId not found');
    await requireWriter(groupId, publisherPeerId);
    final groupData = (await _groupDao.getById(groupId))!;

    final invites = await _inviteService.getByGroupId(groupId);
    final transfers = await _governanceDao.transfersForGroup(groupId);
    final removals = await _governanceDao.removalsForGroup(groupId);
    final dissolution = await _governanceDao.latestDissolution(groupId);

    final body = <String, dynamic>{
      'v': snapshotVersion,
      'group': group.toJson(),
      'invites': invites.map(InviteService.toSnapshotJson).toList(),
      'transfers': transfers.map((t) => t.toJson()).toList(),
      'removals': removals.map((r) => r.toJson()).toList(),
      'dissolution': dissolution?.toJson(),
      'publisher': publisherPeerId,
      'publisherAddrs': publisherAddrs,
      'publishedAt': (groupData.updatedAt ?? DateTime.now().toUtc()).toIso8601String(),
    };
    final sig = await SigningService.sign(snapshotSigningBytes(body), publisherKeyPair);
    return {...body, 'signature': sig.bytes};
  }

  /// Verifies and applies a snapshot from a peer.
  ///
  /// Trust rules (DESIGN_PLAN §9 "verify the signer's role", §19 ordering):
  /// * the signature must verify against the publisher's public key;
  /// * if the group is already known locally, the publisher must be an active
  ///   owner/admin in *our* roster;
  /// * if the group is new (join bootstrap), the publisher must be the owner
  ///   listed in the snapshot and the group's owner signature must verify;
  /// * newer wins: higher sequence number, then later `publishedAt`, then the
  ///   lexicographically greater publisher id (vs [ownPeerId]).
  Future<SnapshotImportResult> importSnapshot(
    Map<String, dynamic> snapshot, {
    String? cid,
    String? ownPeerId,
  }) async {
    final incoming = Group.fromJson(snapshot['group'] as Map<String, dynamic>);
    final publisher = snapshot['publisher'] as String?;
    final signature = (snapshot['signature'] as List?)?.cast<int>();
    final publishedAt = DateTime.tryParse(snapshot['publishedAt'] as String? ?? '')?.toUtc();
    if (publisher == null || signature == null || publishedAt == null) {
      throw StateError('Snapshot is unsigned');
    }

    // --- who signed, and are they allowed to? ---
    final existing = await _groupDao.getById(incoming.id);
    Uint8List publisherKey;
    if (existing != null) {
      final local = await _memberDao.get(publisher, incoming.id);
      if (local == null ||
          local.status != MemberStatus.active.name ||
          !canWrite(_enumByName(MemberRole.values, local.role, MemberRole.member))) {
        throw StateError('Snapshot publisher $publisher is not an owner/admin of this group');
      }
      publisherKey = local.publicKey;
    } else {
      final owner = incoming.owner;
      if (owner == null || owner.peerId != publisher) {
        throw StateError('Initial snapshot must be published by the group owner');
      }
      final ownerOk = await SigningService.verifyWithBytes(
        ownerSigningPayload(incoming.id, owner.peerId),
        incoming.ownerSignature,
        owner.publicKey,
      );
      if (!ownerOk) throw StateError('Group owner signature is invalid');
      publisherKey = owner.publicKey;
    }

    final body = Map<String, dynamic>.from(snapshot)..remove('signature');
    final sigOk = await SigningService.verifyWithBytes(snapshotSigningBytes(body), signature, publisherKey);
    if (!sigOk) throw StateError('Snapshot signature is invalid');

    // --- ordering (§19) ---
    if (existing != null) {
      final localSeq = existing.sequenceNumber;
      final localAt = existing.updatedAt ?? existing.createdAt;
      final newer = incoming.sequenceNumber > localSeq ||
          (incoming.sequenceNumber == localSeq && publishedAt.isAfter(localAt)) ||
          (incoming.sequenceNumber == localSeq &&
              publishedAt.isAtSameMomentAs(localAt) &&
              ownPeerId != null &&
              publisher.compareTo(ownPeerId) > 0);
      if (!newer) {
        if (cid != null) await _groupDao.updateSyncStatus(incoming.id, cid);
        // Invites' used flags are monotonic; merge them regardless.
        await _inviteService.mergeFromSnapshot(
          ((snapshot['invites'] as List?) ?? const [])
              .map((j) => InviteService.fromSnapshotJson(j as Map<String, dynamic>))
              .toList(),
        );
        return SnapshotImportResult((await getGroup(incoming.id))!, false, 'local copy is up to date');
      }
    }

    // --- apply ---
    await _groupDao.upsert(GroupData(
      id: incoming.id,
      name: incoming.name,
      data: incoming.ownerSignature,
      configData: _encodeConfig(incoming.config),
      cid: cid ?? existing?.cid,
      requireApproval: incoming.requireApproval,
      status: incoming.status.name,
      createdAt: incoming.createdAt,
      sequenceNumber: incoming.sequenceNumber,
      updatedAt: publishedAt,
    ));

    // Roster is authoritative: replace, don't merge.
    final incomingIds = incoming.members.map((m) => m.peerId).toSet();
    for (final m in await _memberDao.getByGroupId(incoming.id)) {
      if (!incomingIds.contains(m.peerId)) await _memberDao.delete(m.peerId, incoming.id);
    }
    for (final m in incoming.members) {
      await addMember(groupId: incoming.id, member: m, bumpSequence: false);
    }

    await _inviteService.mergeFromSnapshot(
      ((snapshot['invites'] as List?) ?? const [])
          .map((j) => InviteService.fromSnapshotJson(j as Map<String, dynamic>))
          .toList(),
    );
    for (final t in (snapshot['transfers'] as List?) ?? const []) {
      await _governanceDao.upsertTransfer(OwnershipTransfer.fromJson(t as Map<String, dynamic>));
    }
    for (final r in (snapshot['removals'] as List?) ?? const []) {
      await _governanceDao.insertRemoval(MemberRemoval.fromJson(r as Map<String, dynamic>));
    }
    final d = snapshot['dissolution'];
    if (d != null) {
      await _governanceDao.upsertDissolution(GroupDissolution.fromJson(d as Map<String, dynamic>));
    }

    return SnapshotImportResult((await getGroup(incoming.id))!, true, 'applied');
  }
}
