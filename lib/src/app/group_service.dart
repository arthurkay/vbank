import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../domain/core/failure.dart';
import '../domain/core/result.dart';
import '../domain/governance.dart';
import '../domain/group.dart';
import '../domain/loans.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import 'context.dart';
import 'key_service.dart';
import 'signing_payloads.dart';

/// Failure codes for membership operations. Presentation maps these to
/// messages; services never hold user-facing strings.
abstract final class GroupFailures {
  /// Acting peer is not a member.
  static const String notMember = 'notMember';

  /// Acting peer's membership is not active.
  static const String membershipInactive = 'membershipInactive';

  /// Group is dissolved.
  static const String groupDissolved = 'groupDissolved';

  /// Acting peer may not write.
  static const String notWriter = 'notWriter';

  /// Acting peer may not manage members.
  static const String notManager = 'notManager';

  /// Acting peer is not the owner.
  static const String notOwner = 'notOwner';
}

/// Group roster, config and governance records.
///
/// Every mutation bumps the sequence number: higher wins in conflict
/// resolution. All methods return [Result]; permission problems are
/// [PermissionFailure], missing records [NotFoundFailure], bad input
/// [ValidationFailure], state violations [ConflictFailure].
final class GroupService {
  /// Groups and members.
  final GroupRepository groups;

  /// Removals, transfers, dissolutions.
  final GovernanceRepository governance;

  /// Loans (removal guards).
  final LoanRepository loans;

  /// Group keys (creation).
  final GroupKeyService keys;

  /// Device signer.
  final SignPayload sign;

  /// Clock for timestamps.
  final AppClock clock;

  /// Record ids.
  final IdGenerator ids;

  /// Creates a service.
  GroupService({
    required this.groups,
    required this.governance,
    required this.loans,
    required this.keys,
    required this.sign,
    required this.clock,
    required this.ids,
  });

  /// Loads a group, or `Err(NotFoundFailure)`.
  Future<Result<Group>> getGroup(String groupId) async {
    final Result<Group> group = await groups.findById(groupId);
    return group;
  }

  /// All groups, by name.
  Future<Result<List<Group>>> listGroups() => groups.listAll();

  /// Stores a group as-is (roster flag flips and similar bookkeeping that
  /// must not reorder history carry no sequence bump).
  Future<Result<Unit>> saveGroup(Group group) => groups.save(group);

  /// One member, or null when unknown.
  Future<Member?> getMember(String groupId, String peerId) async {
    final Result<Group> group = await groups.findById(groupId);
    if (group.isErr) {
      return null;
    }
    for (final Member m in group.value.members) {
      if (m.peerId == peerId) {
        return m;
      }
    }
    return null;
  }

  /// The acting member, or a permission failure when unknown or inactive.
  Result<Member> activeMember(Group group, String peerId) {
    Member? found;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        found = m;
      }
    }
    if (found == null) {
      return const Err(PermissionFailure(GroupFailures.notMember));
    }
    if (found.status != MemberStatus.active) {
      return const Err(PermissionFailure(GroupFailures.membershipInactive));
    }
    return Ok(found);
  }

  /// The acting member with [allowed] rank, else a permission failure.
  Result<Member> requireRole(
    Group group,
    String peerId,
    bool Function(MemberRole role) allowed,
    String code,
  ) {
    final Result<Member> member = activeMember(group, peerId);
    if (member.isErr) {
      return member;
    }
    if (!allowed(member.value.role)) {
      return Err(PermissionFailure(code));
    }
    return member;
  }

  /// The acting member with write rank.
  Result<Member> requireWriter(Group group, String peerId) => requireRole(
        group,
        peerId,
        canWrite,
        GroupFailures.notWriter,
      );

  /// The acting member with owner rank.
  Result<Member> requireOwner(Group group, String peerId) => requireRole(
        group,
        peerId,
        (MemberRole r) => r == MemberRole.owner,
        GroupFailures.notOwner,
      );

  /// Fails when the group is dissolved.
  Result<Unit> requireLive(Group group) {
    if (group.status == GroupStatus.dissolved) {
      return const Err(PermissionFailure(GroupFailures.groupDissolved));
    }
    return const Ok(unit);
  }

  /// Creates a group with [ownerPeerId] as owner. With [passphrase] the key
  /// derives from it; otherwise a random key is generated for invite links.
  Future<Result<Group>> createGroup({
    required String name,
    required GroupConfig config,
    String? passphrase,
    required String ownerPeerId,
    required String ownerName,
    required Uint8List ownerPublicKey,
    bool requireApproval = false,
  }) async {
    if (ownerPeerId.isEmpty || ownerName.trim().isEmpty) {
      return const Err(ValidationFailure('ownerIdentityIncomplete'));
    }
    if (passphrase != null && !GroupKeyService.isPassphraseValid(passphrase)) {
      return const Err(ValidationFailure('weakPassphrase'));
    }
    if (config.contributionAmount <= 0) {
      return const Err(ValidationFailure('contributionNotPositive'));
    }
    final String groupId = ids();
    final DateTime now = clock().toUtc();
    final Uint8List signature = await sign(
      SigningPayloads.groupOwner(groupId, ownerPeerId),
    );
    final Group group = Group(
      id: groupId,
      name: name.trim(),
      config: GroupConfig(
        groupId: groupId,
        contributionAmount: config.contributionAmount,
        frequency: config.frequency,
        meetingDayOfWeek: config.meetingDayOfWeek,
        meetingTime: config.meetingTime,
        maxLoanMultiplier: config.maxLoanMultiplier,
        loanInterestRate: config.loanInterestRate,
        latePenaltyRate: config.latePenaltyRate,
        minContributionsForLoan: config.minContributionsForLoan,
        currency: config.currency,
        savingsTarget: config.savingsTarget,
        requireLoanApproval: config.requireLoanApproval,
      ),
      members: [
        Member(
          peerId: ownerPeerId,
          name: ownerName.trim(),
          role: MemberRole.owner,
          joinedAt: now,
          publicKey: ownerPublicKey,
        ),
      ],
      requireApproval: requireApproval,
      createdAt: now,
      ownerSignature: signature,
    );
    final Result<Unit> saved = await groups.save(group);
    if (saved.isErr) {
      return Err(saved.failure);
    }
    final Result<SecretKey> keyed = passphrase == null
        ? await keys.setRandom(groupId)
        : await keys.setFromPassphrase(groupId, passphrase);
    if (keyed.isErr) {
      return Err(keyed.failure);
    }
    return Ok(group);
  }

  /// Upserts a member without permission checks (joins, snapshots,
  /// restores). Callers are the sync layer or an authorised action.
  Future<Result<Unit>> addMember(Group group, Member member) =>
      groups.save(
        group.copyWith(
          members: [...group.members, member],
          sequenceNumber: group.sequenceNumber + 1,
        ),
      );

  /// Approves a pending join (owner/admin). Refuses banned peers: the owner
  /// must lift the removal first.
  Future<Result<Unit>> approveMember({
    required Group group,
    required String actingPeerId,
    required String peerId,
  }) async {
    final Result<Unit> live = requireLive(group);
    if (live.isErr) {
      return live;
    }
    if (requireRole(group, actingPeerId, canManageMembers,
            GroupFailures.notManager)
        .isErr) {
      return const Err(PermissionFailure(GroupFailures.notManager));
    }
    final Result<bool> banned = await isBanned(group.id, peerId);
    if (banned.isErr) {
      return Err(banned.failure);
    }
    if (banned.value) {
      return const Err(PermissionFailure('bannedMember'));
    }
    Member? target;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        target = m;
      }
    }
    if (target == null) {
      return Err(NotFoundFailure('member:$peerId'));
    }
    if (target.status != MemberStatus.pending) {
      return const Ok(unit);
    }
    return _replaceMember(
      group,
      target.copyWith(status: MemberStatus.active),
    );
  }

  /// Rejects a pending join: the request row goes away.
  Future<Result<Unit>> rejectMember({
    required Group group,
    required String actingPeerId,
    required String peerId,
  }) async {
    if (requireRole(group, actingPeerId, canManageMembers,
            GroupFailures.notManager)
        .isErr) {
      return const Err(PermissionFailure(GroupFailures.notManager));
    }
    Member? target;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        target = m;
      }
    }
    if (target == null || target.status != MemberStatus.pending) {
      return const Ok(unit);
    }
    return groups.save(
      group.copyWith(
        members: group.members.where((Member m) => m.peerId != peerId).toList(),
        sequenceNumber: group.sequenceNumber + 1,
      ),
    );
  }

  /// Renames a member in every group they belong to.
  Future<Result<Unit>> renameMember({
    required String peerId,
    required String name,
  }) async {
    if (name.trim().isEmpty) {
      return const Err(ValidationFailure('memberNameEmpty'));
    }
    final Result<List<Group>> all = await groups.listAll();
    if (all.isErr) {
      return Err(all.failure);
    }
    for (final Group group in all.value) {
      var changed = false;
      final List<Member> members = [];
      for (final Member m in group.members) {
        if (m.peerId == peerId && m.name != name.trim()) {
          members.add(m.copyWith(name: name.trim()));
          changed = true;
        } else {
          members.add(m);
        }
      }
      if (changed) {
        final Result<Unit> saved = await groups.save(
          group.copyWith(
            members: members,
            sequenceNumber: group.sequenceNumber + 1,
          ),
        );
        if (saved.isErr) {
          return saved;
        }
      }
    }
    return const Ok(unit);
  }

  /// Owner promotes member→admin or demotes admin→member. Ownership itself
  /// only moves via [transferOwnership].
  Future<Result<Unit>> updateMemberRole({
    required Group group,
    required String actingPeerId,
    required String peerId,
    required MemberRole newRole,
  }) async {
    final Result<Unit> live = requireLive(group);
    if (live.isErr) {
      return live;
    }
    final Result<Member> acting = requireOwner(group, actingPeerId);
    if (acting.isErr) {
      return Err(acting.failure);
    }
    Member? target;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        target = m;
      }
    }
    if (target == null) {
      return Err(NotFoundFailure('member:$peerId'));
    }
    if (newRole == MemberRole.owner ||
        target.role == MemberRole.owner) {
      return const Err(PermissionFailure('useTransferOwnership'));
    }
    if (target.role == newRole) {
      return const Ok(unit);
    }
    return _replaceMember(group, target.copyWith(role: newRole));
  }

  /// Suspends or reinstates. Admins may act on members; only the owner may
  /// act on admins; nobody touches the owner. Use [removeMember] for
  /// removals.
  Future<Result<Unit>> updateMemberStatus({
    required Group group,
    required String actingPeerId,
    required String peerId,
    required MemberStatus newStatus,
  }) async {
    final Result<Unit> live = requireLive(group);
    if (live.isErr) {
      return live;
    }
    final Result<Member> acting = requireRole(
      group,
      actingPeerId,
      canManageMembers,
      GroupFailures.notManager,
    );
    if (acting.isErr) {
      return Err(acting.failure);
    }
    Member? target;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        target = m;
      }
    }
    if (target == null) {
      return Err(NotFoundFailure('member:$peerId'));
    }
    if (target.role == MemberRole.owner) {
      return const Err(PermissionFailure('ownerImmutable'));
    }
    if (target.role == MemberRole.admin &&
        acting.value.role != MemberRole.owner) {
      return const Err(PermissionFailure(GroupFailures.notOwner));
    }
    if (newStatus == MemberStatus.removed) {
      return const Err(ValidationFailure('useRemoveMember'));
    }
    return _replaceMember(group, target.copyWith(status: newStatus));
  }

  /// Owner removes a member. With an active loan the caller passes
  /// [settleOutstandingLoan] to default the loans and record the amount;
  /// otherwise removal is refused. The roster row stays (status removed)
  /// so history still resolves the peer.
  Future<Result<MemberRemoval>> removeMember({
    required Group group,
    required String actingPeerId,
    required String peerId,
    required String reason,
    bool settleOutstandingLoan = false,
  }) async {
    final Result<Unit> live = requireLive(group);
    if (live.isErr) {
      return Err(live.failure);
    }
    final Result<Member> acting = requireRole(
      group,
      actingPeerId,
      canRemove,
      GroupFailures.notOwner,
    );
    if (acting.isErr) {
      return Err(acting.failure);
    }
    Member? target;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        target = m;
      }
    }
    if (target == null) {
      return Err(NotFoundFailure('member:$peerId'));
    }
    if (target.role == MemberRole.owner) {
      return const Err(PermissionFailure('ownerImmutable'));
    }
    if (reason.trim().isEmpty) {
      return const Err(ValidationFailure('removalReasonEmpty'));
    }
    final Result<List<LoanRequest>> loansResult =
        await loans.listByGroup(group.id);
    if (loansResult.isErr) {
      return Err(loansResult.failure);
    }
    final List<LoanRequest> active = loansResult.value
        .where(
          (LoanRequest l) =>
              l.borrowerPeerId == peerId && l.isActive,
        )
        .toList();
    if (active.isNotEmpty && !settleOutstandingLoan) {
      return const Err(PermissionFailure('memberHasActiveLoan'));
    }
    var outstanding = 0.0;
    for (final LoanRequest l in active) {
      outstanding += l.approvedAmount;
      final Result<LoanRequest> current = await loans.findById(l.id);
      if (current.isErr) {
        return Err(current.failure);
      }
      final Result<Unit> defaulted = await loans.saveLoan(
        current.value.copyWith(
          status: LoanStatus.defaulted,
          defaultedAt: clock().toUtc(),
        ),
      );
      if (defaulted.isErr) {
        return Err(defaulted.failure);
      }
    }
    final RemovalAction action = active.isNotEmpty
        ? RemovalAction.settleAndRemove
        : RemovalAction.remove;
    // The signature binds the record id, so the id is fixed first.
    final String removalId = ids();
    final MemberRemoval signed = MemberRemoval(
      id: removalId,
      groupId: group.id,
      removedPeerId: peerId,
      removedByPeerId: actingPeerId,
      reason: reason.trim(),
      hasOutstandingLoan: active.isNotEmpty,
      outstandingAmount: outstanding,
      action: action,
      removedAt: clock().toUtc(),
      adminSignature: await sign(
        SigningPayloads.removal(
          removalId: removalId,
          groupId: group.id,
          removedPeerId: peerId,
          action: action.name,
        ),
      ),
    );
    final Result<Unit> stored = await governance.saveRemoval(signed);
    if (stored.isErr) {
      return Err(stored.failure);
    }
    final Result<Unit> suspended = await _replaceMember(
      group,
      target.copyWith(status: MemberStatus.removed),
    );
    if (suspended.isErr) {
      return Err(suspended.failure);
    }
    return Ok(signed);
  }

  /// True while an unlifted removal exists for [peerId]. Storage errors
  /// propagate: a ban check must fail closed, never admit on a hiccup.
  Future<Result<bool>> isBanned(String groupId, String peerId) async {
    final Result<List<MemberRemoval>> removals =
        await governance.removalsByGroup(groupId);
    if (removals.isErr) {
      return Err(removals.failure);
    }
    return Ok(
      removals.value.any(
        (MemberRemoval r) => r.removedPeerId == peerId && !r.lifted,
      ),
    );
  }

  /// Owner lifts every unlifted removal of [peerId].
  Future<Result<Unit>> liftRemoval({
    required Group group,
    required String actingPeerId,
    required String peerId,
  }) async {
    final Result<Unit> live = requireLive(group);
    if (live.isErr) {
      return live;
    }
    if (requireRole(group, actingPeerId, canRemove, GroupFailures.notOwner)
        .isErr) {
      return const Err(PermissionFailure(GroupFailures.notOwner));
    }
    final Result<List<MemberRemoval>> removals =
        await governance.removalsByGroup(group.id);
    if (removals.isErr) {
      return Err(removals.failure);
    }
    for (final MemberRemoval r in removals.value) {
      if (r.removedPeerId == peerId && !r.lifted) {
        final Result<Unit> lifted = await governance.liftRemoval(r.id);
        if (lifted.isErr) {
          return lifted;
        }
      }
    }
    return _touch(group);
  }

  /// Records a member's X25519 public key (from their key announcement).
  Future<Result<Unit>> setMemberEncKey(
    Group group,
    String peerId,
    Uint8List encKey,
  ) async {
    Member? target;
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        target = m;
      }
    }
    if (target == null) {
      return Err(NotFoundFailure('member:$peerId'));
    }
    return _replaceMember(group, target.copyWith(encKey: encKey));
  }

  /// Updates the rules (owner/admin). The config keeps its group id.
  Future<Result<Unit>> updateGroupConfig({
    required Group group,
    required String actingPeerId,
    required GroupConfig config,
    bool? requireApproval,
  }) async {
    final Result<Unit> live = requireLive(group);
    if (live.isErr) {
      return live;
    }
    if (requireWriter(group, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    final Result<Unit> valid = config.validate();
    if (valid.isErr) {
      return valid;
    }
    return groups.save(
      group.copyWith(
        config: GroupConfig(
          groupId: group.id,
          contributionAmount: config.contributionAmount,
          frequency: config.frequency,
          meetingDayOfWeek: config.meetingDayOfWeek,
          meetingTime: config.meetingTime,
          maxLoanMultiplier: config.maxLoanMultiplier,
          loanInterestRate: config.loanInterestRate,
          latePenaltyRate: config.latePenaltyRate,
          minContributionsForLoan: config.minContributionsForLoan,
          currency: config.currency,
          savingsTarget: config.savingsTarget,
          requireLoanApproval: config.requireLoanApproval,
        ),
        requireApproval: requireApproval ?? group.requireApproval,
        sequenceNumber: group.sequenceNumber + 1,
      ),
    );
  }

  /// Renames the group (owner/admin).
  Future<Result<Unit>> renameGroup({
    required Group group,
    required String actingPeerId,
    required String name,
  }) async {
    if (requireWriter(group, actingPeerId).isErr) {
      return const Err(PermissionFailure(GroupFailures.notWriter));
    }
    if (name.trim().isEmpty) {
      return const Err(ValidationFailure('groupNameEmpty'));
    }
    return groups.save(
      group.copyWith(
        name: name.trim(),
        sequenceNumber: group.sequenceNumber + 1,
      ),
    );
  }

  /// Hands the group to an active admin. The old owner's signature is
  /// recorded now; the new owner countersigns on their device.
  Future<Result<OwnershipTransfer>> transferOwnership({
    required Group group,
    required String actingPeerId,
    required String toPeerId,
  }) async {
    final Result<Unit> live = requireLive(group);
    if (live.isErr) {
      return Err(live.failure);
    }
    if (requireRole(group, actingPeerId, canTransferOwnership,
            GroupFailures.notOwner)
        .isErr) {
      return const Err(PermissionFailure(GroupFailures.notOwner));
    }
    Member? target;
    for (final Member m in group.members) {
      if (m.peerId == toPeerId) {
        target = m;
      }
    }
    if (target == null) {
      return Err(NotFoundFailure('member:$toPeerId'));
    }
    if (target.status != MemberStatus.active ||
        target.role != MemberRole.admin) {
      return const Err(PermissionFailure('transferToActiveAdminOnly'));
    }
    final String id = ids();
    final OwnershipTransfer transfer = OwnershipTransfer(
      id: id,
      groupId: group.id,
      fromPeerId: actingPeerId,
      toPeerId: toPeerId,
      transferredAt: clock().toUtc(),
      oldOwnerSignature: await sign(
        SigningPayloads.transfer(
          transferId: id,
          groupId: group.id,
          fromPeerId: actingPeerId,
          toPeerId: toPeerId,
        ),
      ),
      newOwnerSignature: Uint8List(0),
    );
    final Result<Unit> stored = await governance.saveTransfer(transfer);
    if (stored.isErr) {
      return Err(stored.failure);
    }
    // The acting owner passed requireRole above, so both rows exist.
    final Result<Unit> saved = await groups.save(
      group.copyWith(
        members: [
          for (final Member m in group.members)
            if (m.peerId == actingPeerId)
              m.copyWith(role: MemberRole.admin)
            else if (m.peerId == toPeerId)
              m.copyWith(role: MemberRole.owner)
            else
              m,
        ],
        sequenceNumber: group.sequenceNumber + 1,
      ),
    );
    if (saved.isErr) {
      return Err(saved.failure);
    }
    return Ok(transfer);
  }

  /// Countersigns transfers addressed to [ownPeerId] (their device, once
  /// the transfer arrives). True when anything was signed.
  Future<Result<bool>> countersignTransfer({
    required Group group,
    required String ownPeerId,
  }) async {
    final Result<List<OwnershipTransfer>> transfers =
        await governance.transfersByGroup(group.id);
    if (transfers.isErr) {
      return Err(transfers.failure);
    }
    var signed = false;
    for (final OwnershipTransfer t in transfers.value) {
      if (t.toPeerId != ownPeerId || t.newOwnerSignature.isNotEmpty) {
        continue;
      }
      final Uint8List signature = await sign(
        SigningPayloads.transfer(
          transferId: t.id,
          groupId: t.groupId,
          fromPeerId: t.fromPeerId,
          toPeerId: t.toPeerId,
        ),
      );
      final Result<Unit> stored = await governance.saveTransfer(
        OwnershipTransfer(
          id: t.id,
          groupId: t.groupId,
          fromPeerId: t.fromPeerId,
          toPeerId: t.toPeerId,
          transferredAt: t.transferredAt,
          oldOwnerSignature: t.oldOwnerSignature,
          newOwnerSignature: signature,
        ),
      );
      if (stored.isErr) {
        return Err(stored.failure);
      }
      signed = true;
    }
    if (signed) {
      final Result<Unit> touched = await _touch(group);
      if (touched.isErr) {
        return Err(touched.failure);
      }
    }
    return Ok(signed);
  }

  /// Persists a dissolution stage; a completed stage flips the group to
  /// dissolved. The money movements live in governance operations.
  Future<Result<Unit>> saveDissolution(GroupDissolution dissolution) async {
    final Result<Unit> stored = await governance.saveDissolution(dissolution);
    if (stored.isErr) {
      return stored;
    }
    if (dissolution.status != DissolutionStatus.completed) {
      return _touchId(dissolution.groupId);
    }
    final Result<Group> group = await groups.findById(dissolution.groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    return groups.save(
      group.value.copyWith(
        status: GroupStatus.dissolved,
        sequenceNumber: group.value.sequenceNumber + 1,
      ),
    );
  }

  /// Replaces one member row and bumps the sequence.
  Future<Result<Unit>> _replaceMember(Group group, Member member) =>
      groups.save(
        group.copyWith(
          members: [
            for (final Member m in group.members)
              if (m.peerId == member.peerId) member else m,
          ],
          sequenceNumber: group.sequenceNumber + 1,
        ),
      );

  /// Bumps the sequence number.
  Future<Result<Unit>> _touch(Group group) => groups.save(
        group.copyWith(sequenceNumber: group.sequenceNumber + 1),
      );

  /// Bumps a group loaded by id.
  Future<Result<Unit>> _touchId(String groupId) async {
    final Result<Group> group = await groups.findById(groupId);
    if (group.isErr) {
      return Err(group.failure);
    }
    return _touch(group.value);
  }
}
