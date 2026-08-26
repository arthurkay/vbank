import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/ipfs/sync_manager.dart';
import '../models/group.dart';
import '../services/governance_service.dart';
import '../services/group_key_service.dart';
import '../services/group_service.dart';
import '../services/invite_service.dart';
import 'auth_provider.dart';
import 'ipfs_provider.dart';
import 'data_version.dart';
import 'transaction_provider.dart' show transactionServiceProvider;

/// Per-group symmetric keys (DESIGN_PLAN §12). Shared by GroupService and
/// SyncManager so both see the same cache.
final groupKeyServiceProvider = Provider<GroupKeyService>((ref) => GroupKeyService());

final inviteServiceProvider = Provider<InviteService>((ref) => InviteService());

final groupServiceProvider = Provider<GroupService>((ref) {
  return GroupService(
    groupKeyService: ref.watch(groupKeyServiceProvider),
    inviteService: ref.watch(inviteServiceProvider),
  );
});

final governanceServiceProvider = Provider<GovernanceService>((ref) {
  return GovernanceService(
    groupService: ref.watch(groupServiceProvider),
    transactionService: ref.watch(transactionServiceProvider),
  );
});

class GroupListNotifier extends StateNotifier<AsyncValue<List<Group>>> {
  final Ref _ref;
  final GroupService _service;
  StreamSubscription<SyncChange>? _changesSub;

  GroupListNotifier(this._ref, this._service) : super(const AsyncValue.loading()) {
    loadGroups();
    _changesSub = _ref.read(syncManagerProvider).changes.listen((change) {
      if (change.type == SyncChangeType.group || change.type == SyncChangeType.member) {
        loadGroups();
      }
    });
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> loadGroups() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _service.getAllGroups());
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> refresh() => loadGroups();

  /// Publishes a fresh signed snapshot after a local metadata change so peers
  /// converge. Best effort (offline is fine — the periodic sync retries).
  Future<void> _republish(String groupId) async {
    try {
      await _ref.read(syncManagerProvider).publishGroupSnapshot(groupId);
    } catch (_) {}
    await loadGroups();
    _refreshSelected(groupId);
  }

  void _refreshSelected(String groupId) {
    final selected = _ref.read(selectedGroupProvider);
    if (selected?.id != groupId) return;
    final current = state.value?.where((g) => g.id == groupId).firstOrNull;
    if (current != null) _ref.read(selectedGroupProvider.notifier).state = current;
  }

  Future<Group> createGroup({
    required String name,
    required GroupConfig config,
    required String passphrase,
    bool requireApproval = false,
  }) async {
    final auth = _ref.read(authProvider.notifier);
    final identity = auth.requireIdentity();
    final keyPair = await auth.requireSigningKeyPair();

    final group = await _service.createGroup(
      name: name,
      config: config,
      passphrase: passphrase,
      ownerPeerId: identity.peerId,
      ownerName: identity.displayName,
      ownerPublicKey: identity.publicKey,
      ownerKeyPair: keyPair,
      requireApproval: requireApproval,
    );
    await loadGroups();
    unawaited(_ref.read(syncManagerProvider).publishGroupSnapshot(group.id).catchError((_) => ''));
    return group;
  }

  // --- membership management (owner/admin) -------------------------------------

  String get _me => _ref.read(authProvider.notifier).requireIdentity().peerId;

  Future<void> approveMember(String groupId, String peerId) async {
    await _service.approveMember(groupId: groupId, actingPeerId: _me, peerId: peerId);
    await _republish(groupId);
  }

  Future<void> rejectMember(String groupId, String peerId) async {
    await _service.rejectMember(groupId: groupId, actingPeerId: _me, peerId: peerId);
    await _republish(groupId);
  }

  Future<void> setRole(String groupId, String peerId, MemberRole role) async {
    await _service.updateMemberRole(groupId: groupId, actingPeerId: _me, peerId: peerId, newRole: role);
    await _republish(groupId);
  }

  Future<void> setStatus(String groupId, String peerId, MemberStatus status) async {
    await _service.updateMemberStatus(groupId: groupId, actingPeerId: _me, peerId: peerId, newStatus: status);
    await _republish(groupId);
  }

  Future<void> removeMember(String groupId, String peerId, String reason, {bool writeOffLoan = false}) async {
    final kp = await _ref.read(authProvider.notifier).requireSigningKeyPair();
    await _service.removeMember(
      groupId: groupId,
      actingPeerId: _me,
      actingKeyPair: kp,
      peerId: peerId,
      reason: reason,
      settleOutstandingLoan: writeOffLoan,
    );
    await _republish(groupId);
  }

  Future<void> updateConfig(String groupId, GroupConfig config, {bool? requireApproval, String? name}) async {
    await _service.updateGroupConfig(
        groupId: groupId, actingPeerId: _me, config: config, requireApproval: requireApproval);
    if (name != null) await _service.renameGroup(groupId: groupId, actingPeerId: _me, name: name);
    await _republish(groupId);
  }

  Future<void> transferOwnership(String groupId, String toPeerId) async {
    final kp = await _ref.read(authProvider.notifier).requireSigningKeyPair();
    await _service.transferOwnership(groupId: groupId, actingPeerId: _me, actingKeyPair: kp, toPeerId: toPeerId);
    await _republish(groupId);
  }

  Future<void> dissolveGroup(String groupId) async {
    final kp = await _ref.read(authProvider.notifier).requireSigningKeyPair();
    await _ref.read(governanceServiceProvider).dissolveGroup(groupId: groupId, actingPeerId: _me, actingKeyPair: kp);
    // Distribution transactions go out on the next sync; snapshot now.
    bumpDataVersion(_ref);
    await _republish(groupId);
    unawaited(_ref.read(syncManagerProvider).startManualSync());
  }
}

final groupListProvider = StateNotifierProvider<GroupListNotifier, AsyncValue<List<Group>>>((ref) {
  return GroupListNotifier(ref, ref.watch(groupServiceProvider));
});

final selectedGroupProvider = StateProvider<Group?>((ref) => null);

/// The current user's membership in the selected group (null if not a member).
final myMembershipProvider = Provider<Member?>((ref) {
  // `selectedGroupProvider` is the copy taken when the group was opened; a
  // snapshot from the owner (e.g. approving this member) updates the list, so
  // read the live copy or the "waiting for approval" screen never goes away.
  final selected = ref.watch(selectedGroupProvider);
  final group = ref.watch(groupListProvider).value?.where((g) => g.id == selected?.id).firstOrNull ?? selected;
  final me = ref.watch(authProvider).identity?.peerId;
  if (group == null || me == null) return null;
  return group.members.where((m) => m.peerId == me).firstOrNull;
});

/// Convenience flags for the UI (DESIGN_PLAN §13).
final canWriteProvider = Provider<bool>((ref) {
  final m = ref.watch(myMembershipProvider);
  if (m == null || m.status != MemberStatus.active) return false;
  return ref.watch(groupServiceProvider).canWrite(m.role);
});

final isOwnerProvider = Provider<bool>((ref) {
  final m = ref.watch(myMembershipProvider);
  return m != null && m.status == MemberStatus.active && m.role == MemberRole.owner;
});
