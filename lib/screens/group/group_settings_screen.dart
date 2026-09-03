import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/role_badge.dart';

/// DESIGN_PLAN §27 group_settings + ownership_transfer + group_dissolution.
/// Every action is permission-checked again in GroupService; the UI only
/// hides what the current role can't do (§13).
class GroupSettingsScreen extends ConsumerStatefulWidget {
  const GroupSettingsScreen({super.key});

  @override
  ConsumerState<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends ConsumerState<GroupSettingsScreen> {
  bool _busy = false;
  final _memberSearch = TextEditingController();
  String _memberQuery = '';

  @override
  void dispose() {
    _memberSearch.dispose();
    super.dispose();
  }

  void _msg(String m, {bool error = false}) {
    if (mounted) showMessage(context, m, error: error);
  }

  Future<void> _run(Future<void> Function() a, [String? ok]) async {
    setState(() => _busy = true);
    try {
      await a();
      if (ok != null) _msg(ok);
    } catch (e) {
      _msg('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final selected = ref.watch(selectedGroupProvider);
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == selected?.id).firstOrNull ?? selected;
    final me = ref.watch(authProvider).identity?.peerId;
    final my = ref.watch(myMembershipProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final canManage = ref.watch(canWriteProvider);
    if (group == null || my == null) {
      return const AppPage(title: 'Group settings', child: EmptyState(icon: LucideIcons.users, title: 'No group selected'));
    }
    final notifier = ref.read(groupListProvider.notifier);
    final pending = group.members.where((m) => m.status == MemberStatus.pending).toList();
    final roster = group.members.where((m) => m.status != MemberStatus.pending && m.status != MemberStatus.removed).toList()
      ..sort((a, b) => a.role.index != b.role.index ? a.role.index.compareTo(b.role.index) : a.name.compareTo(b.name));
    final dissolved = group.status == GroupStatus.dissolved;
    final cfg = group.config;
    final scheme = Theme.of(context).colorScheme;

    return AppPage(
      title: 'Settings',
      subtitle: Text(group.name),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (dissolved) ...[
            const Alert.destructive(
              leading: Icon(LucideIcons.info),
              content: Text('This group has been dissolved. Records are read-only.'),
            ),
            const Gap(12),
          ],
          // --- config -------------------------------------------------------
          ListRow(
            leading: const Icon(LucideIcons.settings2),
            title: const Text('Group configuration'),
            subtitle: Text(
              '${fmtMoney(cfg.currency, cfg.contributionAmount)} ${cfg.frequency.name} · '
              'interest ${(cfg.loanInterestRate * 100).toStringAsFixed(0)}% · '
              'max loan ${cfg.maxLoanMultiplier}× · join ${group.requireApproval ? 'approval' : 'instant'}',
            ).small.muted,
            trailing: canManage && !dissolved ? const Icon(LucideIcons.pencil) : null,
            onTap: canManage && !dissolved ? () => _editConfig(group, notifier) : null,
          ),

          // --- pending approvals -----------------------------------------------
          if (canManage && pending.isNotEmpty) ...[
            const SectionTitle('Waiting for approval'),
            for (final m in pending)
              ListRow(
                leading: const Icon(LucideIcons.hourglass),
                title: Text(m.name),
                subtitle: Text('Requested ${fmtDateTime(m.joinedAt)}').small.muted,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton.ghost(
                      icon: Icon(LucideIcons.check, color: scheme.primary),
                      onPressed: _busy ? null : () => _run(() => notifier.approveMember(group.id, m.peerId), '${m.name} approved'),
                    ),
                    IconButton.ghost(
                      icon: Icon(LucideIcons.x, color: scheme.destructive),
                      onPressed: _busy ? null : () => _run(() => notifier.rejectMember(group.id, m.peerId), '${m.name} rejected'),
                    ),
                  ],
                ),
              ),
          ],

          // --- members ---------------------------------------------------------
          SectionTitle('Members', trailing: Text('${roster.length}').xSmall.muted),
          if (roster.length >= 6) ...[
            SearchField(
              controller: _memberSearch,
              placeholder: 'Search members',
              onChanged: (v) => setState(() => _memberQuery = v),
            ),
            const Gap(10),
          ],
          for (final m in roster.where((m) => _memberQuery.trim().isEmpty ||
              '${m.name} ${m.role.name} ${m.status.name}'.toLowerCase().contains(_memberQuery.trim().toLowerCase())))
            Builder(builder: (context) {
              final isMe = m.peerId == me;
              final actions = <ActionMenuItem>[];
              if (!dissolved && !isMe && m.role != MemberRole.owner) {
                if (isOwner && m.role == MemberRole.member) {
                  actions.add(ActionMenuItem('Make admin', () => _memberAction('promote', group, m, notifier),
                      icon: LucideIcons.shieldCheck));
                }
                if (isOwner && m.role == MemberRole.admin) {
                  actions.add(ActionMenuItem('Remove admin role', () => _memberAction('demote', group, m, notifier),
                      icon: LucideIcons.shieldOff));
                  actions.add(ActionMenuItem('Transfer ownership', () => _memberAction('transfer', group, m, notifier),
                      icon: LucideIcons.arrowLeftRight));
                }
                if (canManage && (isOwner || m.role == MemberRole.member)) {
                  final suspended = m.status == MemberStatus.suspended;
                  actions.add(ActionMenuItem(
                    suspended ? 'Reinstate' : 'Suspend',
                    () => _memberAction(suspended ? 'reinstate' : 'suspend', group, m, notifier),
                    icon: suspended ? LucideIcons.play : LucideIcons.pause,
                  ));
                }
                if (isOwner) {
                  actions.add(ActionMenuItem('Remove from group', () => _memberAction('remove', group, m, notifier),
                      icon: LucideIcons.userMinus));
                }
              }
              return ListRow(
                leading: InitialsAvatar(m.name),
                title: Text('${m.name}${isMe ? ' (you)' : ''}'),
                subtitle: Text(m.status == MemberStatus.active ? 'Active' : m.status.name).small.muted,
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RoleBadge(role: m.role.name),
                    if (actions.isNotEmpty) ActionMenu(items: actions, enabled: !_busy),
                  ],
                ),
              );
            }),

          // --- removed members (banned until the owner allows them back) ----------
          if (isOwner && !dissolved) _RemovedMembers(group: group, busy: _busy, onAllowBack: (peerId) async {
            setState(() => _busy = true);
            try {
              await notifier.allowBack(group.id, peerId);
              if (context.mounted) showMessage(context, 'They can be invited again');
            } catch (e) {
              if (context.mounted) showMessage(context, '$e', error: true);
            } finally {
              if (mounted) setState(() => _busy = false);
            }
          }),

          // --- danger zone -------------------------------------------------------
          if (isOwner && !dissolved) ...[
            const SectionTitle('Owner actions'),
            Button.destructive(
              onPressed: _busy ? null : () => _dissolve(group, notifier),
              leading: const Icon(LucideIcons.trash2),
              child: const Text('Dissolve group'),
            ),
            const Gap(8),
            const Text(
              'Dissolving requires all loans settled and no pending reversals. Each member is paid out their '
              'net balance and the group becomes read-only.',
            ).small.muted,
          ],
          const Gap(24),
        ],
      ),
    );
  }

  Future<void> _memberAction(String action, Group group, Member m, GroupListNotifier notifier) async {
    switch (action) {
      case 'promote':
        await _run(() => notifier.setRole(group.id, m.peerId, MemberRole.admin), '${m.name} is now an admin');
        break;
      case 'demote':
        await _run(() => notifier.setRole(group.id, m.peerId, MemberRole.member), '${m.name} is now a member');
        break;
      case 'suspend':
        await _run(() => notifier.setStatus(group.id, m.peerId, MemberStatus.suspended), '${m.name} suspended');
        break;
      case 'reinstate':
        await _run(() => notifier.setStatus(group.id, m.peerId, MemberStatus.active), '${m.name} reinstated');
        break;
      case 'transfer':
        final ok = await confirmSheet(
          context,
          title: 'Transfer ownership to ${m.name}?',
          message: 'You will become an admin. ${m.name}\'s phone will countersign when it next syncs.',
          confirmLabel: 'Transfer',
        );
        if (ok) await _run(() => notifier.transferOwnership(group.id, m.peerId), 'Ownership transferred to ${m.name}');
        break;
      case 'remove':
        final c = TextEditingController();
        var writeOff = false;
        final ok = await showAppSheet<bool>(
          context,
          title: 'Remove ${m.name}?',
          builder: (ctx, close) => StatefulBuilder(
            builder: (ctx, setS) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                LabeledField(label: 'Reason', child: TextField(cursorOpacityAnimates: false, controller: c, autofocus: true)),
                if (m.hasOutstandingLoan) ...[
                  const Gap(16),
                  Checkbox(
                    state: writeOff ? CheckboxState.checked : CheckboxState.unchecked,
                    onChanged: (v) => setS(() => writeOff = v == CheckboxState.checked),
                    trailing: const Text('Write off outstanding loan'),
                  ),
                  const Gap(4),
                  const Text('Marks the loan defaulted and records the amount').small.muted,
                ],
                const Gap(24),
                Button.destructive(onPressed: () => close(true), child: const Text('Remove')),
                const Gap(8),
                OutlineButton(onPressed: () => close(false), child: const Text('Cancel')),
              ],
            ),
          ),
        );
        if (ok == true) {
          await _run(
            () => notifier.removeMember(group.id, m.peerId, c.text.trim().isEmpty ? 'Removed by owner' : c.text.trim(),
                writeOffLoan: writeOff),
            '${m.name} removed',
          );
        }
        break;
    }
  }

  Future<void> _editConfig(Group group, GroupListNotifier notifier) async {
    final cfg = group.config;
    final name = TextEditingController(text: group.name);
    final amount = TextEditingController(text: cfg.contributionAmount.toStringAsFixed(2));
    final interest = TextEditingController(text: (cfg.loanInterestRate * 100).toStringAsFixed(0));
    final multiplier = TextEditingController(text: cfg.maxLoanMultiplier.toString());
    final minContrib = TextEditingController(text: cfg.minContributionsForLoan.toString());
    final penalty = TextEditingController(text: (cfg.latePenaltyRate * 100).toStringAsFixed(0));
    var frequency = cfg.frequency;
    var requireLoanApproval = cfg.requireLoanApproval;
    var requireApproval = group.requireApproval;

    Widget toggle(String label, bool value, ValueChanged<bool> onChanged) => Row(
          children: [
            Expanded(child: Text(label)),
            Switch(value: value, onChanged: onChanged),
          ],
        );

    final ok = await showAppSheet<bool>(
      context,
      title: 'Group configuration',
      builder: (ctx, close) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledField(label: 'Group name', child: TextField(cursorOpacityAnimates: false, controller: name, textCapitalization: TextCapitalization.words)),
            const Gap(16),
            LabeledField(
              label: 'Contribution (${cfg.currency})',
              child: TextField(cursorOpacityAnimates: false, controller: amount, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
            ),
            const Gap(16),
            LabeledField(
              label: 'Frequency',
              child: Segmented<ContributionFrequency>(
                values: ContributionFrequency.values,
                selected: frequency,
                label: (f) => f.name,
                onChanged: (f) => setS(() => frequency = f),
              ),
            ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Loan interest (%)',
                    child: TextField(cursorOpacityAnimates: false, controller: interest, keyboardType: TextInputType.number),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: LabeledField(
                    label: 'Late penalty (%)',
                    child: TextField(cursorOpacityAnimates: false, controller: penalty, keyboardType: TextInputType.number),
                  ),
                ),
              ],
            ),
            const Gap(16),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: 'Max loan (× contributions)',
                    child: TextField(cursorOpacityAnimates: false, controller: multiplier, keyboardType: const TextInputType.numberWithOptions(decimal: true)),
                  ),
                ),
                const Gap(12),
                Expanded(
                  child: LabeledField(
                    label: 'Min contributions',
                    child: TextField(cursorOpacityAnimates: false, controller: minContrib, keyboardType: TextInputType.number),
                  ),
                ),
              ],
            ),
            const Gap(20),
            toggle('Loans need admin approval', requireLoanApproval, (v) => setS(() => requireLoanApproval = v)),
            const Gap(12),
            toggle('New members need approval', requireApproval, (v) => setS(() => requireApproval = v)),
            const Gap(24),
            Button.primary(onPressed: () => close(true), child: const Text('Save')),
            const Gap(8),
            OutlineButton(onPressed: () => close(false), child: const Text('Cancel')),
          ],
        ),
      ),
    );
    if (ok != true) return;

    final newCfg = GroupConfig(
      groupId: group.id,
      contributionAmount: double.tryParse(amount.text) ?? cfg.contributionAmount,
      frequency: frequency,
      meetingDayOfWeek: cfg.meetingDayOfWeek,
      meetingTime: cfg.meetingTime,
      maxLoanMultiplier: double.tryParse(multiplier.text) ?? cfg.maxLoanMultiplier,
      loanInterestRate: (double.tryParse(interest.text) ?? cfg.loanInterestRate * 100) / 100,
      latePenaltyRate: (double.tryParse(penalty.text) ?? cfg.latePenaltyRate * 100) / 100,
      minContributionsForLoan: int.tryParse(minContrib.text) ?? cfg.minContributionsForLoan,
      currency: cfg.currency,
      savingsTarget: cfg.savingsTarget,
      requireLoanApproval: requireLoanApproval,
    );
    await _run(
      () => notifier.updateConfig(group.id, newCfg,
          requireApproval: requireApproval, name: name.text.trim() != group.name ? name.text.trim() : null),
      'Configuration saved',
    );
  }

  Future<void> _dissolve(Group group, GroupListNotifier notifier) async {
    final blockers = await ref.read(governanceServiceProvider).dissolutionBlockers(group.id);
    if (!mounted) return;
    if (blockers.isNotEmpty) {
      _msg('Cannot dissolve: ${blockers.join('; ')}', error: true);
      return;
    }
    final ok = await confirmSheet(
      context,
      title: 'Dissolve ${group.name}?',
      message: 'Every member will be paid out their net balance and the group becomes read-only. This cannot be undone.',
      confirmLabel: 'Dissolve',
      destructive: true,
    );
    if (ok) await _run(() => notifier.dissolveGroup(group.id), 'Group dissolved');
  }
}


/// People the owner removed. They cannot re-join (their invites are refused
/// and the group key was rotated) until allowed back here.
class _RemovedMembers extends ConsumerWidget {
  final Group group;
  final bool busy;
  final Future<void> Function(String peerId) onAllowBack;
  const _RemovedMembers({required this.group, required this.busy, required this.onAllowBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FutureBuilder(
      future: ref.read(groupServiceProvider).bannedMembers(group.id),
      builder: (context, snap) {
        final banned = snap.data ?? const [];
        if (banned.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SectionTitle('Removed members', trailing: Text('${banned.length}').xSmall.muted),
            for (final r in banned)
              ListRow(
                leading: const Icon(LucideIcons.userX),
                title: Text(group.members.where((m) => m.peerId == r.removedPeerId).firstOrNull?.name ?? 'Former member'),
                subtitle: Text('Removed ${fmtDate(r.removedAt)} · ${r.reason}').small.muted,
                trailing: Button.outline(
                  onPressed: busy ? null : () => onAllowBack(r.removedPeerId),
                  child: const Text('Allow back'),
                ),
              ),
            const Text('Removed members cannot re-join, even with a new invite link, until you allow them back.')
                .xSmall
                .muted,
          ],
        );
      },
    );
  }
}
