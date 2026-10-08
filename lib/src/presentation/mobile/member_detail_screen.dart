import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../member/member_actions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// One member with management actions in shadcn dress. The buttons
/// shown come from [availableActions], so they match what the service
/// will accept; removal of a debtor offers settlement.
final class MobileMemberDetailScreen extends ConsumerStatefulWidget {
  /// The group containing the member.
  final String groupId;

  /// The member shown.
  final String peerId;

  /// Creates the screen.
  const MobileMemberDetailScreen({
    super.key,
    required this.groupId,
    required this.peerId,
  });

  @override
  ConsumerState<MobileMemberDetailScreen> createState() =>
      _MobileMemberDetailScreenState();
}

final class _MobileMemberDetailScreenState
    extends ConsumerState<MobileMemberDetailScreen> {
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
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: Text(target?.name ?? 'Member'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (target == null)
            const Text('No longer in this group.').small.muted
          else ...[
            Row(
              children: [
                Text(target.name).xLarge.bold,
                const Gap(8),
                SecondaryBadge(
                  child: Text(target.role.name),
                ),
              ],
            ),
            const Gap(8),
            Text('Status: ${target.status.name}').small.muted,
            if (target.hasOutstandingLoan) ...[
              const Gap(8),
              const Text('Has an outstanding loan.').small,
            ],
            const Gap(20),
            if (self != null && g != null)
              for (final MemberAction action in availableActions(
                self.role,
                target,
              )) ...[
                if (action == MemberAction.remove &&
                    target.hasOutstandingLoan)
                  Text(
                    'Removing settles their loans as defaulted.',
                  ).small.muted,
                if (action == MemberAction.remove &&
                    target.hasOutstandingLoan)
                  const Gap(8),
                PrimaryButton(
                  onPressed: _busy ? null : () => _run(g, target!, action),
                  child: Text(_busy ? 'Working…' : actionLabel(action)),
                ),
                const Gap(8),
              ],
            if (_error != null) ...[
              Text(_error!).small,
              const Gap(12),
            ],
          ],
        ],
      ),
    );
  }
}
