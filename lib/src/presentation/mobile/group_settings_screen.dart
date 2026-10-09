import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/governance.dart';
import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import 'sheets.dart';

/// Owner settings in shadcn dress: transfer ownership to an admin and
/// dissolve the group once loans and corrections settle. Bottom-sheet
/// confirms guard both irreversible actions.
final class MobileGroupSettingsScreen extends ConsumerStatefulWidget {
  /// The group administered.
  final String groupId;

  /// Creates the screen.
  const MobileGroupSettingsScreen({super.key, required this.groupId});

  @override
  ConsumerState<MobileGroupSettingsScreen> createState() =>
      _MobileGroupSettingsScreenState();
}

final class _MobileGroupSettingsScreenState
    extends ConsumerState<MobileGroupSettingsScreen> {
  String? _adminId;
  String? _error;
  bool _busy = false;

  /// Transfers ownership to the picked admin, confirmed in a sheet:
  /// the old owner becomes an admin and cannot undo it.
  Future<void> _transfer(Group group, String me) async {
    final String? toPeerId = _adminId;
    if (toPeerId == null) {
      setState(() => _error = 'Pick an admin first.');
      return;
    }
    String toName = toPeerId;
    for (final Member m in group.members) {
      if (m.peerId == toPeerId) {
        toName = m.name;
      }
    }
    final bool ok = await confirmSheet(
      context,
      title: 'Transfer ownership',
      body:
          'Make $toName the owner of ${group.name}? You become an admin. '
          'This cannot be undone.',
      actionLabel: 'Transfer',
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<OwnershipTransfer> result = await ref
        .read(appServicesProvider)
        .groups
        .transferOwnership(
          group: group,
          actingPeerId: me,
          toPeerId: toPeerId,
        );
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (result.isErr) {
        _error = _explain(result.failure);
      }
    });
  }

  /// Dissolves the group, paying out positive balances. The sheet states
  /// what happens; the button below stays disabled while blockers exist.
  Future<void> _dissolve(Group group, String me) async {
    final bool ok = await confirmSheet(
      context,
      title: 'Dissolve group',
      body:
          'Wind up ${group.name} and pay every positive balance out? '
          'The ledger stays as a read-only archive. This cannot be undone.',
      actionLabel: 'Dissolve',
      danger: true,
    );
    if (!ok || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<List<Transaction>> payouts = await ref
        .read(appServicesProvider)
        .governance
        .dissolveGroup(groupId: group.id, actingPeerId: me);
    if (!mounted) {
      return;
    }
    setState(() {
      _busy = false;
      if (payouts.isErr) {
        _error = _explain(payouts.failure);
      }
    });
  }

  /// Machine failure codes to human words.
  static String _explain(Failure failure) => switch (failure) {
    PermissionFailure(:final action) => 'Not allowed ($action).',
    ValidationFailure(:final reason) => 'Check the request ($reason).',
    NotFoundFailure(:final subject) => 'Missing $subject.',
    ConflictFailure(:final subject) => 'Blocked: $subject.',
    NetworkFailure() => 'No connection.',
    IntegrityFailure(:final subject) => 'Rejected $subject.',
    StorageFailure() => 'Storage failed.',
  };

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final String? me = ref.watch(authProvider).identity?.peerId;
    final Group? g = group.valueOrNull;
    Member? self;
    if (g != null && me != null) {
      for (final Member m in g.members) {
        if (m.peerId == me) {
          self = m;
        }
      }
    }
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Group settings'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (g == null || self?.role != MemberRole.owner) ...[
            const Text(
              'Only the group owner changes these settings.',
            ).small.muted,
          ] else ...[
            Text('Transfer ownership').small.semiBold.muted,
            const Gap(8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final Member m in g.members)
                  if (m.role == MemberRole.admin &&
                      m.status == MemberStatus.active)
                    _adminId == m.peerId
                        ? PrimaryButton(
                            onPressed: () => setState(
                              () => _adminId = null,
                            ),
                            child: Text(m.name),
                          )
                        : OutlineButton(
                            onPressed: () => setState(
                              () => _adminId = m.peerId,
                            ),
                            child: Text(m.name),
                          ),
              ],
            ),
            const Gap(8),
            PrimaryButton(
              key: const ValueKey('transfer-button'),
              onPressed: _busy ? null : () => _transfer(g, me!),
              child: Text(_busy ? 'Working…' : 'Transfer ownership'),
            ),
            const Gap(20),
            _DissolveSection(
              group: g,
              busy: _busy,
              onDissolve: () => _dissolve(g, me!),
            ),
            if (_error != null) ...[
              const Gap(12),
              Text(_error!).small,
            ],
          ],
        ],
      ),
    );
  }
}

/// Dissolution blockers or the dissolve action (confirmed in a sheet).
final class _DissolveSection extends ConsumerWidget {
  /// The group wound up.
  final Group group;

  /// A dissolve in flight.
  final bool busy;

  /// Runs dissolve after the sheet confirm.
  final Future<void> Function() onDissolve;

  /// Creates the section.
  const _DissolveSection({
    required this.group,
    required this.busy,
    required this.onDissolve,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<String>> blockers = ref.watch(
      _blockersProvider(group.id),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Dissolve group').small.semiBold.muted,
        const Gap(8),
        blockers.when(
          loading: () =>
              const Center(child: CircularProgressIndicator()),
          error: (Object error, _) => Text('Error: $error').small,
          data: (List<String> items) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (items.isEmpty)
                const Text(
                  'No outstanding loans or corrections. Dissolving pays '
                  'every positive balance out.',
                ).small.muted
              else
                for (final String b in items) Text('• $b').small,
              const Gap(8),
              PrimaryButton(
                onPressed: busy || items.isNotEmpty ? null : onDissolve,
                child: Text(busy ? 'Working…' : 'Dissolve group'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Dissolution blockers for a group.
final _blockersProvider =
    FutureProvider.autoDispose.family<List<String>, String>(
  (ref, groupId) => ref
      .watch(appServicesProvider)
      .governance
      .dissolutionBlockers(groupId)
      .then((r) => r.isOk ? r.value : <String>['Could not check.']),
);
