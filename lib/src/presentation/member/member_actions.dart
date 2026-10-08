import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../app_scope.dart';
import '../providers/auth.dart';

/// Member management actions, mirrored from [GroupService] rules so
/// screens offer only what will succeed. Pure and unit-tested.
enum MemberAction {
  /// member → admin (owner only).
  promote,

  /// admin → member (owner only).
  demote,

  /// active → suspended.
  suspend,

  /// suspended → active.
  activate,

  /// Off the roster (owner only, settles loans).
  remove,
}

/// Actions [mine] may take on [target]. Empty for self and the owner.
List<MemberAction> availableActions(MemberRole mine, Member target) {
  if (target.role == MemberRole.owner ||
      target.status == MemberStatus.removed) {
    return const [];
  }
  final List<MemberAction> actions = [];
  if (mine == MemberRole.owner) {
    if (target.role == MemberRole.member) {
      actions.add(MemberAction.promote);
    } else {
      actions.add(MemberAction.demote);
    }
  }
  final bool manages =
      canManageMembers(mine) &&
      (target.role == MemberRole.member || mine == MemberRole.owner);
  if (manages) {
    if (target.status == MemberStatus.active) {
      actions.add(MemberAction.suspend);
    } else if (target.status == MemberStatus.suspended) {
      actions.add(MemberAction.activate);
    }
  }
  if (mine == MemberRole.owner && target.status != MemberStatus.removed) {
    actions.add(MemberAction.remove);
  }
  return actions;
}

/// Runs [action] through the services. Returns a human message, or null
/// on success (callers pop).
Future<String?> runMemberAction(
  WidgetRef ref, {
  required Group group,
  required Member target,
  required MemberAction action,
  String reason = 'Removed by owner',
  bool settleLoans = false,
}) async {
  final String? actingPeerId = ref.read(authProvider).identity?.peerId;
  if (actingPeerId == null) {
    return 'Sign in first.';
  }
  final groups = ref.read(appServicesProvider).groups;
  Result<Unit> result;
  switch (action) {
    case MemberAction.promote:
      result = await groups.updateMemberRole(
        group: group,
        actingPeerId: actingPeerId,
        peerId: target.peerId,
        newRole: MemberRole.admin,
      );
    case MemberAction.demote:
      result = await groups.updateMemberRole(
        group: group,
        actingPeerId: actingPeerId,
        peerId: target.peerId,
        newRole: MemberRole.member,
      );
    case MemberAction.suspend:
      result = await groups.updateMemberStatus(
        group: group,
        actingPeerId: actingPeerId,
        peerId: target.peerId,
        newStatus: MemberStatus.suspended,
      );
    case MemberAction.activate:
      result = await groups.updateMemberStatus(
        group: group,
        actingPeerId: actingPeerId,
        peerId: target.peerId,
        newStatus: MemberStatus.active,
      );
    case MemberAction.remove:
      final removal = await groups.removeMember(
        group: group,
        actingPeerId: actingPeerId,
        peerId: target.peerId,
        reason: reason,
        settleOutstandingLoan: settleLoans,
      );
      if (removal.isErr) {
        return _explain(removal.failure);
      }
      return null;
  }
  return result.isErr ? _explain(result.failure) : null;
}

/// Machine failure codes to human words.
String _explain(Failure failure) => switch (failure) {
  PermissionFailure(:final action) => switch (action) {
    'memberHasActiveLoan' =>
      'They still owe the group — remove with settlement.',
    _ => 'Not allowed ($action).',
  },
  ValidationFailure(:final reason) => 'Check the request ($reason).',
  NotFoundFailure(:final subject) => 'Missing $subject.',
  ConflictFailure(:final subject) => 'Conflict on $subject.',
  NetworkFailure() => 'No connection.',
  IntegrityFailure(:final subject) => 'Rejected $subject.',
  StorageFailure() => 'Storage failed.',
};

/// Label for an action button.
String actionLabel(MemberAction action) => switch (action) {
  MemberAction.promote => 'Make admin',
  MemberAction.demote => 'Remove admin',
  MemberAction.suspend => 'Suspend',
  MemberAction.activate => 'Reinstate',
  MemberAction.remove => 'Remove',
};

/// This device's role in [group], or null when outside it.
MemberRole? myRole(Group? group, String? peerId) {
  if (group == null || peerId == null) {
    return null;
  }
  for (final Member m in group.members) {
    if (m.peerId == peerId) {
      return m.role;
    }
  }
  return null;
}

/// True when this device may record (owners and admins only).
bool canRecord(Group? group, String? peerId) {
  final MemberRole? role = myRole(group, peerId);
  return role != null && canWrite(role);
}
