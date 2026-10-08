import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../member/member_actions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// One member with management actions in Yaru dress. The buttons shown
/// come from [availableActions], so they match what the service will
/// accept; removal of a debtor offers settlement.
final class LinuxMemberDetailPage extends ConsumerStatefulWidget {
  /// The group containing the member.
  final String groupId;

  /// The member shown.
  final String peerId;

  /// Creates the page.
  const LinuxMemberDetailPage({
    super.key,
    required this.groupId,
    required this.peerId,
  });

  @override
  ConsumerState<LinuxMemberDetailPage> createState() =>
      _LinuxMemberDetailPageState();
}

final class _LinuxMemberDetailPageState
    extends ConsumerState<LinuxMemberDetailPage> {
  String? _error;
  bool _busy = false;

  /// Runs [action], popping back to the detail on removal.
  Future<void> _run(
    Group group,
    Member target,
    MemberAction action,
  ) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    final String? error = await runMemberAction(
      ref,
      group: group,
      target: target,
      action: action,
      settleLoans: action == MemberAction.remove &&
          target.hasOutstandingLoan,
    );
    if (!mounted) {
      return;
    }
    if (error != null) {
      setState(() {
        _busy = false;
        _error = error;
      });
      return;
    }
    if (action == MemberAction.remove) {
      Navigator.pop(context);
      return;
    }
    setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final String? me = ref.read(authProvider).identity?.peerId;
    final Group? g = group.valueOrNull;
    Member? target;
    Member? self;
    if (g != null) {
      for (final Member m in g.members) {
        if (m.peerId == widget.peerId) {
          target = m;
        }
        if (m.peerId == me) {
          self = m;
        }
      }
    }
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
        title: Text(target?.name ?? 'Member'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          if (target == null)
            const Text('No longer in this group.')
          else ...[
            Row(
              children: [
                Text(
                  target.name,
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(width: 8),
                Chip(label: Text(target.role.name)),
              ],
            ),
            const SizedBox(height: 8),
            Text('Status: ${target.status.name}'),
            if (target.hasOutstandingLoan) ...[
              const SizedBox(height: 8),
              const Text('Has an outstanding loan.'),
            ],
            const SizedBox(height: 20),
            if (self != null && g != null)
              for (final MemberAction action in availableActions(
                self.role,
                target,
              )) ...[
                if (action == MemberAction.remove &&
                    target.hasOutstandingLoan)
                  const Text(
                    'Removing settles their loans as defaulted.',
                  ),
                if (action == MemberAction.remove &&
                    target.hasOutstandingLoan)
                  const SizedBox(height: 8),
                FilledButton(
                  onPressed: _busy ? null : () => _run(g, target!, action),
                  child: Text(_busy ? 'Working…' : actionLabel(action)),
                ),
                const SizedBox(height: 8),
              ],
            if (_error != null) ...[
              Text(_error!),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
    );
  }
}
