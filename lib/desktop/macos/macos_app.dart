/// The macOS shell: macos_ui.
///
/// Apple's idiom — a [MacosWindow] with a source-list sidebar, a [ToolBar] per
/// page, [MacosTabView] for a group's sections, sheets for forms and
/// [MacosAlertDialog] for confirmations.
library;

import 'package:flutter/cupertino.dart' show CupertinoIcons, CupertinoPageRoute;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../core/app_bootstrap.dart';
import '../../core/ipfs/sync_manager.dart';
import '../../core/presentation/list_filters.dart';
import '../../core/storage/settings_dao.dart';
import '../../core/storage/transaction_dao.dart' as q;
import '../../models/repayment_schedule.dart';
import '../../models/app_backup.dart';
import '../../models/group.dart';
import '../../models/loan.dart';
import '../../models/meeting.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/balance_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/ipfs_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/backup_service.dart';
import 'macos_actions.dart';
import 'macos_kit.dart';

class VBankMacosApp extends ConsumerWidget {
  const VBankMacosApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MacosApp(
      title: 'vBank',
      debugShowCheckedModeBanner: false,
      theme: MacosThemeData.light(),
      darkTheme: MacosThemeData.dark(),
      home: const AppBootstrap(child: _MacosRoot()),
    );
  }
}

class _MacosRoot extends ConsumerWidget {
  const _MacosRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoaded) {
      return const MacosWindow(child: MacosScaffold(children: [ContentArea(builder: _loading)]));
    }
    if (!auth.isLoggedIn) return const MacosOnboarding();
    return const MacosShell();
  }

  static Widget _loading(BuildContext context, ScrollController _) =>
      const Center(child: ProgressCircle());
}

// -----------------------------------------------------------------------------
// Shell
// -----------------------------------------------------------------------------

class MacosShell extends ConsumerStatefulWidget {
  const MacosShell({super.key});

  @override
  ConsumerState<MacosShell> createState() => _MacosShellState();
}

class _MacosShellState extends ConsumerState<MacosShell> {
  int _index = 0;
  String? _openGroupId;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];
    final open = groups.where((g) => g.id == _openGroupId).firstOrNull;

    if (open != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(selectedGroupProvider)?.id != open.id) {
          ref.read(selectedGroupProvider.notifier).state = open;
        }
      });
    }

    return MacosWindow(
      sidebar: Sidebar(
        minWidth: 220,
        builder: (context, scrollController) => SidebarItems(
          currentIndex: _index,
          onChanged: (i) => setState(() {
            _index = i;
            _openGroupId = null;
          }),
          scrollController: scrollController,
          items: const [
            SidebarItem(leading: MacosIcon(CupertinoIcons.person_2), label: Text('Groups')),
            SidebarItem(leading: MacosIcon(CupertinoIcons.list_bullet), label: Text('Activity')),
            SidebarItem(leading: MacosIcon(CupertinoIcons.calendar), label: Text('Meetings')),
            SidebarItem(leading: MacosIcon(CupertinoIcons.arrow_2_circlepath), label: Text('Sync')),
            SidebarItem(leading: MacosIcon(CupertinoIcons.settings), label: Text('Settings')),
          ],
        ),
      ),
      child: switch (_index) {
        0 => open == null
            ? MacosGroupsPage(onOpen: (id) => setState(() => _openGroupId = id))
            : MacosGroupPage(group: open, onBack: () => setState(() => _openGroupId = null)),
        1 => const MacosActivityPage(),
        2 => const MacosMeetingsPage(),
        3 => const MacosSyncPage(),
        _ => const MacosSettingsPage(),
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Onboarding
// -----------------------------------------------------------------------------

class MacosOnboarding extends ConsumerWidget {
  const MacosOnboarding({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final typography = MacosTheme.of(context).typography;
    return MacosWindow(
      child: MacosScaffold(
        children: [
          ContentArea(
            builder: (context, controller) => Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const MacosIcon(CupertinoIcons.person_2_square_stack, size: 64),
                    const SizedBox(height: 20),
                    Text('vBank', style: typography.largeTitle),
                    const SizedBox(height: 8),
                    Text(
                      'Village banking that works offline. Your group’s books live on this Mac and sync '
                      'directly with your members’ devices.',
                      textAlign: TextAlign.center,
                      style: typography.body,
                    ),
                    const SizedBox(height: 28),
                    PushButton(
                      controlSize: ControlSize.large,
                      onPressed: () => macosCreateIdentity(context, ref),
                      child: const Text('Get started'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Groups
// -----------------------------------------------------------------------------

class MacosGroupsPage extends ConsumerWidget {
  final ValueChanged<String> onOpen;
  const MacosGroupsPage({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupListProvider);

    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Groups'),
        actions: [
          ToolBarIconButton(
            label: 'Join a group',
            icon: const MacosIcon(CupertinoIcons.square_arrow_down),
            showLabel: false,
            onPressed: () => macosJoinGroup(context, ref),
          ),
          ToolBarIconButton(
            label: 'New group',
            icon: const MacosIcon(CupertinoIcons.add),
            showLabel: false,
            onPressed: () => macosCreateGroup(context, ref),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, controller) => groupsAsync.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (e, _) => MacosEmpty(
              icon: CupertinoIcons.exclamationmark_triangle,
              title: 'Could not load groups',
              subtitle: '$e',
            ),
            data: (list) {
              if (list.isEmpty) {
                return MacosEmpty(
                  icon: CupertinoIcons.person_2,
                  title: 'No groups yet',
                  subtitle: 'Create a savings group, or join one with an invite link.',
                  action: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      PushButton(
                        controlSize: ControlSize.large,
                        onPressed: () => macosCreateGroup(context, ref),
                        child: const Text('New group'),
                      ),
                      const SizedBox(width: 8),
                      PushButton(
                        controlSize: ControlSize.large,
                        secondary: true,
                        onPressed: () => macosJoinGroup(context, ref),
                        child: const Text('Join a group'),
                      ),
                    ],
                  ),
                );
              }
              return MacosFilteredList<Group>(
                items: list,
                searchHint: 'Search groups',
                searchText: groupHaystack,
                builder: (context, visible) => ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => _MacosGroupRow(group: visible[i], onOpen: onOpen),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MacosGroupRow extends ConsumerWidget {
  final Group group;
  final ValueChanged<String> onOpen;
  const _MacosGroupRow({required this.group, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(groupBalancesProvider(group.id)).value;
    final fund = balances?.fold<double>(0, (sum, b) => sum + b.netBalance) ?? 0;
    final pending = group.members.where((m) => m.status == MemberStatus.pending).length;

    return MacosListTile(
      leading: const MacosIcon(CupertinoIcons.person_2_fill),
      title: Text(group.name, style: MacosTheme.of(context).typography.headline),
      subtitle: Text([
        '${group.memberCount} members',
        '${fmtMoney(group.config.currency, group.config.contributionAmount)} ${group.config.frequency.name}',
        'fund ${fmtMoney(group.config.currency, fund)}',
        if (pending > 0) '$pending awaiting approval',
        if (group.status == GroupStatus.dissolved) 'dissolved',
      ].join(' · ')),
      onClick: () => onOpen(group.id),
    );
  }
}

/// One group with a macOS tab view of sections.
class MacosGroupPage extends ConsumerStatefulWidget {
  final Group group;
  final VoidCallback onBack;
  const MacosGroupPage({super.key, required this.group, required this.onBack});

  @override
  ConsumerState<MacosGroupPage> createState() => _MacosGroupPageState();
}

class _MacosGroupPageState extends ConsumerState<MacosGroupPage> {
  late final MacosTabController _tabs = MacosTabController(length: 5);

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final canWrite = ref.watch(canWriteProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final my = ref.watch(myMembershipProvider);
    final dissolved = group.status == GroupStatus.dissolved;
    final pendingMe = my?.status == MemberStatus.pending;

    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(onPressed: widget.onBack, fillColor: const Color(0x00000000)),
        title: Text(group.name),
        actions: [
          if (canWrite && !dissolved)
            ToolBarIconButton(
              label: 'Invite members',
              icon: const MacosIcon(CupertinoIcons.person_add),
              showLabel: false,
              onPressed: () => macosShowInvite(context, ref, group),
            ),
          if (canWrite && !dissolved)
            ToolBarIconButton(
              label: 'Group configuration',
              icon: const MacosIcon(CupertinoIcons.slider_horizontal_3),
              showLabel: false,
              onPressed: () => macosEditGroupConfig(context, ref, group),
            ),
          if (isOwner && !dissolved)
            ToolBarIconButton(
              label: 'Dissolve group',
              icon: const MacosIcon(CupertinoIcons.trash),
              showLabel: false,
              onPressed: () => macosDissolveGroup(context, ref, group),
            ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, controller) => pendingMe
              ? const MacosEmpty(
                  icon: CupertinoIcons.clock,
                  title: 'Waiting for approval',
                  subtitle: 'An admin of this group needs to approve your request.',
                )
              : MacosTabView(
                  controller: _tabs,
                  tabs: const [
                    MacosTab(label: 'Overview'),
                    MacosTab(label: 'Transactions'),
                    MacosTab(label: 'Members'),
                    MacosTab(label: 'Loans'),
                    MacosTab(label: 'Meetings'),
                  ],
                  children: [
                    _MacosOverview(group: group),
                    _MacosTransactions(group: group),
                    _MacosMembers(group: group),
                    _MacosLoans(group: group),
                    _MacosMeetings(group: group),
                  ],
                ),
        ),
      ],
    );
  }
}

class _MacosOverview extends ConsumerWidget {
  final Group group;
  const _MacosOverview({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = group.config;
    final me = ref.watch(authProvider).identity?.peerId;
    final mine = me == null ? null : ref.watch(balanceProvider((peerId: me, groupId: group.id))).value;
    final fund = ref.watch(groupFundProvider(group.id)).value;
    final canWrite = ref.watch(canWriteProvider);
    final dissolved = group.status == GroupStatus.dissolved;

    return ListView(
      padding: vbankMacPadding,
      children: [
        Row(children: [
          Expanded(
            child: MacosStatTile(
                label: 'Group fund', value: fmtMoney(cfg.currency, fund?.total ?? 0), emphasise: true),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MacosStatTile(
                label: 'Available to lend', value: fmtMoney(cfg.currency, fund?.available ?? 0)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MacosStatTile(label: 'Out on loan', value: fmtMoney(cfg.currency, fund?.lentOut ?? 0)),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: MacosStatTile(
                label: 'My net balance', value: fmtMoney(cfg.currency, mine?.netBalance ?? 0)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MacosStatTile(
                label: 'My contributions', value: fmtMoney(cfg.currency, mine?.totalContributed ?? 0)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: MacosStatTile(
                label: 'Interest still expected', value: fmtMoney(cfg.currency, fund?.interestExpected ?? 0)),
          ),
        ]),
        const SizedBox(height: 16),
        if (!dissolved)
          Row(children: [
            if (canWrite)
              PushButton(
                controlSize: ControlSize.large,
                onPressed: () => macosRecordTransaction(context, ref, group),
                child: const Text('Record transaction'),
              ),
            const SizedBox(width: 8),
            PushButton(
              controlSize: ControlSize.large,
              secondary: true,
              onPressed: () => macosRequestLoan(context, ref, group),
              child: const Text('Request a loan'),
            ),
            const SizedBox(width: 8),
            if (canWrite)
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => macosScheduleMeeting(context, ref, group),
                child: const Text('Schedule meeting'),
              ),
          ]),
        const SizedBox(height: 16),
        MacosGroupBox(
          label: 'Group rules',
          children: [
            MacosInfoRow('Contribution',
                '${fmtMoney(cfg.currency, cfg.contributionAmount)} ${cfg.frequency.name}'),
            MacosInfoRow('Loan interest', '${(cfg.loanInterestRate * 100).toStringAsFixed(0)}%'),
            MacosInfoRow('Late penalty', '${(cfg.latePenaltyRate * 100).toStringAsFixed(0)}%'),
            MacosInfoRow('Maximum loan', '${cfg.maxLoanMultiplier}× contributions'),
            MacosInfoRow('Minimum contributions', '${cfg.minContributionsForLoan}'),
            MacosInfoRow('Loan approval', cfg.requireLoanApproval ? 'Admin approval' : 'Automatic'),
            MacosInfoRow('Joining', group.requireApproval ? 'Needs approval' : 'Instant with an invite'),
          ],
        ),
      ],
    );
  }
}

class _MacosTransactions extends ConsumerWidget {
  final Group group;
  const _MacosTransactions({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionListProvider(group.id));
    return txs.when(
      loading: () => const Center(child: ProgressCircle()),
      error: (e, _) => MacosEmpty(
          icon: CupertinoIcons.exclamationmark_triangle, title: 'Could not load transactions', subtitle: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return const MacosEmpty(
            icon: CupertinoIcons.list_bullet,
            title: 'No transactions yet',
            subtitle: 'Admins record contributions, penalties and withdrawals here.',
          );
        }
        return MacosFilteredList<Transaction>(
          items: list,
          filters: transactionFilters(),
          searchHint: 'Search transactions',
          searchText: (tx) => transactionHaystack(tx, group: group),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: visible.length,
            itemBuilder: (context, i) => MacosTransactionRow(transaction: visible[i], group: group),
          ),
        );
      },
    );
  }
}

class MacosTransactionRow extends ConsumerWidget {
  final Transaction transaction;
  final Group? group;
  final bool showGroup;
  const MacosTransactionRow({
    super.key,
    required this.transaction,
    required this.group,
    this.showGroup = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = transaction;
    final theme = MacosTheme.of(context);
    final reversed = tx.status == TransactionStatus.reversed;
    String nameOf(String peerId) => peerId == 'group'
        ? 'Group fund'
        : group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? 'member';

    return MacosListTile(
      leading: MacosIcon(switch (tx.type) {
        TransactionType.contribution => CupertinoIcons.arrow_down_circle,
        TransactionType.loan => CupertinoIcons.building_2_fill,
        TransactionType.repayment => CupertinoIcons.arrow_2_circlepath,
        TransactionType.withdrawal => CupertinoIcons.arrow_up_circle,
        TransactionType.penalty || TransactionType.fee => CupertinoIcons.exclamationmark_circle,
        TransactionType.reversal => CupertinoIcons.arrow_uturn_left,
      }),
      title: Text(
        '${titleCase(tx.type.name)} · ${fmtMoney(tx.currency, tx.amount)}',
        style: theme.typography.headline.copyWith(
          decoration: reversed ? TextDecoration.lineThrough : null,
        ),
      ),
      subtitle: Text([
        if (showGroup && group != null) group!.name,
        fmtDate(tx.timestamp),
        '${nameOf(tx.fromPeerId)} → ${nameOf(tx.toPeerId)}',
        if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
      ].join(' · ')),
      onClick: () => _detail(context, ref, nameOf),
    );
  }

  void _detail(BuildContext context, WidgetRef ref, String Function(String) nameOf) {
    final tx = transaction;
    final canWrite = ref.read(canWriteProvider);
    final me = ref.read(authProvider).identity?.peerId;
    final reversals = (ref.read(reversalsProvider(tx.groupId)).value ?? const [])
        .where((r) => r.originalTransactionId == tx.id)
        .toList();
    final pending = reversals.where((r) => r.isPending).firstOrNull;
    final involved = tx.fromPeerId == me || tx.toPeerId == me;

    macosSheet<void>(
      context,
      title: titleCase(tx.type.name),
      width: 520,
      content: (context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          MacosGroupBox(children: [
            MacosInfoRow('Amount', fmtMoney(tx.currency, tx.amount)),
            MacosInfoRow('Status', titleCase(tx.status.name)),
            MacosInfoRow('From', nameOf(tx.fromPeerId)),
            MacosInfoRow('To', nameOf(tx.toPeerId)),
            MacosInfoRow('Recorded by', nameOf(tx.authorPeerId)),
            MacosInfoRow('When', fmtDateTime(tx.timestamp)),
            if (tx.note != null && tx.note!.isNotEmpty) MacosInfoRow('Note', tx.note!),
            MacosInfoRow('Sequence', '#${tx.sequenceNumber}'),
          ]),
          if (reversals.isNotEmpty) ...[
            const SizedBox(height: 12),
            MacosGroupBox(
              label: 'Reversals',
              children: [
                for (final r in reversals)
                  MacosRow(
                    title: Text('${titleCase(r.status.name)} — ${r.reason}'),
                    subtitle: Text('by ${nameOf(r.requestedByPeerId)}'),
                    trailing: r.isPending && canWrite && r.requestedByPeerId != me
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            PushButton(
                              controlSize: ControlSize.small,
                              onPressed: () {
                                Navigator.pop(context);
                                macosDecideReversal(context, ref, tx.groupId, r.id, approve: true);
                              },
                              child: const Text('Approve'),
                            ),
                            const SizedBox(width: 6),
                            PushButton(
                              controlSize: ControlSize.small,
                              secondary: true,
                              onPressed: () {
                                Navigator.pop(context);
                                macosDecideReversal(context, ref, tx.groupId, r.id, approve: false);
                              },
                              child: const Text('Reject'),
                            ),
                          ])
                        : null,
                  ),
              ],
            ),
          ],
        ],
      ),
      actions: (context) => [
        if (tx.status == TransactionStatus.confirmed && pending == null && (involved || canWrite))
          PushButton(
            controlSize: ControlSize.large,
            secondary: true,
            onPressed: () {
              Navigator.pop(context);
              macosRequestReversal(context, ref, tx);
            },
            child: const Text('Request reversal'),
          ),
        PushButton(
          controlSize: ControlSize.large,
          onPressed: () => Navigator.pop(context),
          child: const Text('Close'),
        ),
      ],
    );
  }
}

class _MacosMembers extends ConsumerWidget {
  final Group group;
  const _MacosMembers({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final me = ref.watch(authProvider).identity?.peerId;
    final isOwner = ref.watch(isOwnerProvider);
    final canWrite = ref.watch(canWriteProvider);
    final dissolved = group.status == GroupStatus.dissolved;
    final members = group.members.where((m) => m.status != MemberStatus.removed).toList()
      ..sort((a, b) => a.role.index != b.role.index
          ? a.role.index.compareTo(b.role.index)
          : a.name.compareTo(b.name));

    if (members.isEmpty) {
      return const MacosEmpty(icon: CupertinoIcons.person_2, title: 'No members yet');
    }

    return MacosFilteredList<Member>(
      items: members,
      filters: memberFilters(),
      searchHint: 'Search members',
      searchText: memberHaystack,
      builder: (context, visible) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        itemCount: visible.length,
        itemBuilder: (context, i) {
          final member = visible[i];
          final balance = ref.watch(balanceProvider((peerId: member.peerId, groupId: group.id))).value;
          final isMe = member.peerId == me;
          final actions = <String>[
            if (member.status == MemberStatus.pending && canWrite) 'approve',
            if (member.status == MemberStatus.pending && canWrite) 'reject',
            if (!dissolved && !isMe && member.role != MemberRole.owner) ...[
              if (isOwner && member.role == MemberRole.member) 'promote',
              if (isOwner && member.role == MemberRole.admin) 'demote',
              if (isOwner && member.role == MemberRole.admin) 'transfer',
              if (canWrite && (isOwner || member.role == MemberRole.member))
                member.status == MemberStatus.suspended ? 'reinstate' : 'suspend',
              if (isOwner) 'remove',
            ],
          ];

          return MacosRow(
            leading: const MacosIcon(CupertinoIcons.person_crop_circle),
            title: Text('${member.name}${isMe ? ' (you)' : ''}',
                style: MacosTheme.of(context).typography.headline),
            subtitle: Text([
              titleCase(member.role.name),
              member.status == MemberStatus.active
                  ? 'contributed ${fmtMoney(group.config.currency, balance?.totalContributed ?? 0)}'
                  : member.status.name,
              if (member.hasOutstandingLoan) 'has a loan',
            ].join(' · ')),
            trailing: actions.isEmpty
                ? null
                : MacosPulldownButton(
                    icon: CupertinoIcons.ellipsis_circle,
                    items: [
                      for (final a in actions)
                        MacosPulldownMenuItem(
                          title: Text(_label(a)),
                          onTap: () => macosMemberAction(context, ref, group, member, a),
                        ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  static String _label(String action) => switch (action) {
        'approve' => 'Approve join request',
        'reject' => 'Reject join request',
        'promote' => 'Make admin',
        'demote' => 'Remove admin role',
        'transfer' => 'Transfer ownership',
        'suspend' => 'Suspend',
        'reinstate' => 'Reinstate',
        'remove' => 'Remove from group',
        _ => action,
      };
}

class _MacosLoans extends ConsumerWidget {
  final Group group;
  const _MacosLoans({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loanListProvider(group.id));
    return loans.when(
      loading: () => const Center(child: ProgressCircle()),
      error: (e, _) => MacosEmpty(
          icon: CupertinoIcons.exclamationmark_triangle, title: 'Could not load loans', subtitle: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return MacosEmpty(
            icon: CupertinoIcons.building_2_fill,
            title: 'No loans yet',
            subtitle: 'Members request loans; admins approve and disburse them.',
            action: PushButton(
              controlSize: ControlSize.large,
              onPressed: () => macosRequestLoan(context, ref, group),
              child: const Text('Request a loan'),
            ),
          );
        }
        String borrowerOf(LoanRequest l) =>
            group.members.where((m) => m.peerId == l.borrowerPeerId).firstOrNull?.name ?? 'member';

        return MacosFilteredList<LoanRequest>(
          items: list,
          filters: loanFilters(),
          searchHint: 'Search loans',
          searchText: (l) => loanHaystack(l, borrower: borrowerOf(l)),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final loan = visible[i];
              return MacosRow(
                leading: const MacosIcon(CupertinoIcons.building_2_fill),
                title: Text('${fmtMoney(group.config.currency, loan.requestedAmount)} · ${borrowerOf(loan)}',
                    style: MacosTheme.of(context).typography.headline),
                subtitle: Text('${titleCase(loan.status.name)} · ${loan.termWeeks} weeks'),
                trailing: MacosStatusChip(loan.status.name),
                onTap: () => Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => MacosLoanDetailPage(groupId: group.id, loanId: loan.id),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _MacosMeetings extends ConsumerWidget {
  final Group group;
  const _MacosMeetings({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(meetingListProvider(group.id));
    final canWrite = ref.watch(canWriteProvider) && group.status != GroupStatus.dissolved;

    return meetings.when(
      loading: () => const Center(child: ProgressCircle()),
      error: (e, _) => MacosEmpty(
          icon: CupertinoIcons.exclamationmark_triangle, title: 'Could not load meetings', subtitle: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return MacosEmpty(
            icon: CupertinoIcons.calendar,
            title: 'No meetings yet',
            subtitle: 'Schedule the next one before the group leaves.',
            action: canWrite
                ? PushButton(
                    controlSize: ControlSize.large,
                    onPressed: () => macosScheduleMeeting(context, ref, group),
                    child: const Text('Schedule meeting'),
                  )
                : null,
          );
        }
        return MacosFilteredList<Meeting>(
          items: list,
          filters: meetingFilters(),
          searchHint: 'Search meetings',
          searchText: (m) => meetingHaystack(m),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final m = visible[i];
              final present = m.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
              return MacosListTile(
                leading: const MacosIcon(CupertinoIcons.calendar),
                title: Text(fmtDateTime(m.scheduledAt), style: MacosTheme.of(context).typography.headline),
                subtitle: Text([
                  titleCase(m.status.name),
                  '$present present',
                  if (m.status == MeetingStatus.completed)
                    'collected ${fmtMoney(group.config.currency, m.totalCollected)}',
                ].join(' · ')),
                onClick: () => Navigator.of(context).push(
                  CupertinoPageRoute(
                    builder: (_) => MacosMeetingDetailPage(groupId: group.id, meetingId: m.id),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Activity / meetings across groups
// -----------------------------------------------------------------------------

class MacosActivityPage extends ConsumerWidget {
  const MacosActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(allTransactionsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];

    return MacosScaffold(
      toolBar: const ToolBar(title: Text('Activity')),
      children: [
        ContentArea(
          builder: (context, controller) => txs.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (e, _) => MacosEmpty(
                icon: CupertinoIcons.exclamationmark_triangle, title: 'Could not load activity', subtitle: '$e'),
            data: (list) {
              if (list.isEmpty) {
                return const MacosEmpty(
                  icon: CupertinoIcons.list_bullet,
                  title: 'No transactions yet',
                  subtitle: 'Records you and your co-admins make will appear here.',
                );
              }
              Group? groupOf(Transaction tx) => groups.where((g) => g.id == tx.groupId).firstOrNull;
              return MacosFilteredList<Transaction>(
                items: list,
                filters: transactionFilters(),
                searchHint: 'Search activity',
                searchText: (tx) => transactionHaystack(tx, group: groupOf(tx)),
                builder: (context, visible) => ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: visible.length,
                  itemBuilder: (context, i) => MacosTransactionRow(
                    transaction: visible[i],
                    group: groupOf(visible[i]),
                    showGroup: true,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class MacosMeetingsPage extends ConsumerWidget {
  const MacosMeetingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(upcomingMeetingsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];

    return MacosScaffold(
      toolBar: const ToolBar(title: Text('Upcoming meetings')),
      children: [
        ContentArea(
          builder: (context, controller) => meetings.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (e, _) => MacosEmpty(
                icon: CupertinoIcons.exclamationmark_triangle, title: 'Could not load meetings', subtitle: '$e'),
            data: (list) {
              if (list.isEmpty) {
                return const MacosEmpty(
                  icon: CupertinoIcons.calendar,
                  title: 'No meetings scheduled',
                  subtitle: 'Schedule one from a group’s Meetings tab.',
                );
              }
              String nameOf(Meeting m) => groups.where((g) => g.id == m.groupId).firstOrNull?.name ?? 'Meeting';
              return MacosFilteredList<Meeting>(
                items: list,
                filters: meetingFilters(),
                searchHint: 'Search meetings',
                searchText: (m) => meetingHaystack(m, group: nameOf(m)),
                builder: (context, visible) => ListView.builder(
                  controller: controller,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: visible.length,
                  itemBuilder: (context, i) {
                    final m = visible[i];
                    final group = groups.where((g) => g.id == m.groupId).firstOrNull;
                    return MacosListTile(
                      leading: const MacosIcon(CupertinoIcons.calendar),
                      title: Text(nameOf(m), style: MacosTheme.of(context).typography.headline),
                      subtitle: Text('${fmtDateTime(m.scheduledAt)} · ${m.status.name}'),
                      onClick: group == null
                          ? null
                          : () {
                              ref.read(selectedGroupProvider.notifier).state = group;
                              Navigator.of(context).push(
                                CupertinoPageRoute(
                                  builder: (_) =>
                                      MacosMeetingDetailPage(groupId: group.id, meetingId: m.id),
                                ),
                              );
                            },
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Loan / meeting detail
// -----------------------------------------------------------------------------

class MacosLoanDetailPage extends ConsumerWidget {
  final String groupId;
  final String loanId;
  const MacosLoanDetailPage({super.key, required this.groupId, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final loanAsync = ref.watch(loanProvider(loanId));
    final scheduleAsync = ref.watch(loanScheduleProvider(loanId));
    final progress = ref.watch(loanProgressProvider(loanId)).value;
    final canWrite = ref.watch(canWriteProvider);
    final me = ref.watch(authProvider).identity?.peerId;

    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(onPressed: () => Navigator.of(context).pop()),
        title: const Text('Loan'),
      ),
      children: [
        ContentArea(
          builder: (context, controller) => loanAsync.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (e, _) => MacosEmpty(
                icon: CupertinoIcons.exclamationmark_triangle, title: 'Could not load loan', subtitle: '$e'),
            data: (loan) {
              if (loan == null || group == null) {
                return const MacosEmpty(icon: CupertinoIcons.building_2_fill, title: 'Loan not found');
              }
              final currency = group.config.currency;
              final borrower = group.members.where((m) => m.peerId == loan.borrowerPeerId).firstOrNull;
              final isBorrower = me == loan.borrowerPeerId;
              final schedule = scheduleAsync.value ?? const [];

              return ListView(
                controller: controller,
                padding: vbankMacPadding,
                children: [
                  Row(children: [
                    Text(fmtMoney(currency, loan.requestedAmount),
                        style: MacosTheme.of(context).typography.title1),
                    const SizedBox(width: 12),
                    MacosStatusChip(loan.status.name),
                  ]),
                  const SizedBox(height: 16),
                  MacosGroupBox(
                    label: 'Loan',
                    children: [
                      MacosInfoRow('Borrower', borrower?.name ?? loan.borrowerPeerId),
                      MacosInfoRow('Term', '${loan.termWeeks} weeks'),
                      MacosInfoRow('Interest', '${(loan.interestRate * 100).toStringAsFixed(0)}%'),
                      if (loan.approvedAmount > 0)
                        MacosInfoRow('Approved', fmtMoney(currency, loan.approvedAmount)),
                      if (loan.approvedAmount > 0)
                        MacosInfoRow('Total due', fmtMoney(currency, loan.totalWithInterest)),
                      if (progress != null && progress.totalDue > 0) ...[
                        MacosInfoRow('Repaid so far', fmtMoney(currency, progress.repaid)),
                        MacosInfoRow('Still owed', fmtMoney(currency, progress.remaining)),
                      ],
                      if (loan.reason != null && loan.reason!.isNotEmpty)
                        MacosInfoRow('Reason', loan.reason!),
                      MacosInfoRow('Requested', fmtDateTime(loan.requestedAt)),
                      if (loan.disbursedAt != null)
                        MacosInfoRow('Disbursed', fmtDateTime(loan.disbursedAt!)),
                      if (loan.completedAt != null)
                        MacosInfoRow('Completed', fmtDateTime(loan.completedAt!)),
                    ],
                  ),
                  if (canWrite) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      if (loan.status == LoanStatus.pending && !isBorrower) ...[
                        PushButton(
                          controlSize: ControlSize.large,
                          onPressed: () => macosApproveLoan(context, ref, group, loan),
                          child: const Text('Approve'),
                        ),
                        const SizedBox(width: 8),
                        PushButton(
                          controlSize: ControlSize.large,
                          secondary: true,
                          onPressed: () => macosRejectLoan(context, ref, group, loan),
                          child: const Text('Reject'),
                        ),
                      ],
                      if (loan.status == LoanStatus.approved)
                        PushButton(
                          controlSize: ControlSize.large,
                          onPressed: () => macosDisburseLoan(context, ref, group, loan),
                          child: const Text('Record disbursement'),
                        ),
                      if (loan.isActive)
                        PushButton(
                          controlSize: ControlSize.large,
                          onPressed: () => macosRecordRepayment(context, ref, group, loan, schedule),
                          child: const Text('Record repayment'),
                        ),
                    ]),
                  ],
                  if (schedule.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    MacosGroupBox(
                      label: 'Repayment schedule',
                      children: [
                        for (final s in schedule)
                          MacosRow(
                            leading: MacosIcon(s.isPaid
                                ? CupertinoIcons.checkmark_circle
                                : s.isOverdue
                                    ? CupertinoIcons.exclamationmark_circle
                                    : CupertinoIcons.clock),
                            title: Text(
                                'Installment ${s.installmentNumber} — ${fmtMoney(currency, s.expectedAmount)}'),
                            subtitle: Text(
                              'Due ${fmtDate(s.dueDate)}'
                              '${s.paidAmount > 0 ? ' · paid ${s.paidAmount.toStringAsFixed(2)}' : ''}'
                              '${s.penalty > 0 ? ' · penalty ${s.penalty.toStringAsFixed(2)}' : ''}',
                            ),
                            trailing: MacosStatusChip(s.status.label),
                          ),
                      ],
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class MacosMeetingDetailPage extends ConsumerWidget {
  final String groupId;
  final String meetingId;
  const MacosMeetingDetailPage({super.key, required this.groupId, required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final meetingAsync = ref.watch(meetingProvider(meetingId));
    final canWrite = ref.watch(canWriteProvider);

    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(onPressed: () => Navigator.of(context).pop()),
        title: const Text('Meeting'),
      ),
      children: [
        ContentArea(
          builder: (context, controller) => meetingAsync.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (e, _) => MacosEmpty(
                icon: CupertinoIcons.exclamationmark_triangle, title: 'Could not load meeting', subtitle: '$e'),
            data: (meeting) {
              if (meeting == null || group == null) {
                return const MacosEmpty(icon: CupertinoIcons.calendar, title: 'Meeting not found');
              }
              final editable = canWrite && meeting.status == MeetingStatus.scheduled;
              final members = group.members.where((m) => m.status == MemberStatus.active).toList()
                ..sort((a, b) => a.name.compareTo(b.name));
              final present =
                  meeting.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
              final contributed = meeting.attendance.where((a) => a.contributed).length;

              return ListView(
                controller: controller,
                padding: vbankMacPadding,
                children: [
                  Row(children: [
                    Text(fmtDateTime(meeting.scheduledAt),
                        style: MacosTheme.of(context).typography.title1),
                    const SizedBox(width: 12),
                    MacosStatusChip(meeting.status.name),
                  ]),
                  const SizedBox(height: 16),
                  MacosGroupBox(
                    label: 'Summary',
                    children: [
                      MacosInfoRow('Present', '$present / ${members.length}'),
                      MacosInfoRow('Contributed', '$contributed'),
                      if (meeting.status == MeetingStatus.completed)
                        MacosInfoRow('Collected', fmtMoney(group.config.currency, meeting.totalCollected)),
                      if (meeting.notes != null && meeting.notes!.isNotEmpty)
                        MacosInfoRow('Notes', meeting.notes!),
                    ],
                  ),
                  const SizedBox(height: 16),
                  MacosGroupBox(
                    label: 'Attendance',
                    children: [
                      for (final m in members)
                        _MacosAttendanceRow(
                          group: group,
                          meeting: meeting,
                          member: m,
                          editable: editable,
                        ),
                    ],
                  ),
                  if (editable) ...[
                    const SizedBox(height: 16),
                    Row(children: [
                      PushButton(
                        controlSize: ControlSize.large,
                        onPressed: () => macosCompleteMeeting(context, ref, group, meeting, contributed),
                        child: const Text('Complete meeting'),
                      ),
                      const SizedBox(width: 8),
                      PushButton(
                        controlSize: ControlSize.large,
                        secondary: true,
                        onPressed: () => macosCancelMeeting(context, ref, group, meeting),
                        child: const Text('Cancel meeting'),
                      ),
                    ]),
                  ],
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MacosAttendanceRow extends ConsumerWidget {
  final Group group;
  final Meeting meeting;
  final Member member;
  final bool editable;
  const _MacosAttendanceRow({
    required this.group,
    required this.meeting,
    required this.member,
    required this.editable,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = meeting.attendance.where((a) => a.peerId == member.peerId).firstOrNull;
    final status = record?.status ?? MeetingAttendanceStatus.absent;
    final paid = record?.contributed ?? false;
    const statuses = [
      MeetingAttendanceStatus.present,
      MeetingAttendanceStatus.excused,
      MeetingAttendanceStatus.absent,
    ];

    return MacosRow(
      title: Text(member.name),
      subtitle: Text('${titleCase(status.name)}${paid ? ' · contributed' : ''}'),
      trailing: !editable
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                MacosPopupButton<MeetingAttendanceStatus>(
                  value: status,
                  items: [
                    for (final s in statuses)
                      MacosPopupMenuItem(value: s, child: Text(titleCase(s.name))),
                  ],
                  onChanged: (s) => macosSetAttendance(
                    ref,
                    group,
                    meeting,
                    member.peerId,
                    s ?? status,
                    contributed: paid,
                  ),
                ),
                const SizedBox(width: 10),
                MacosCheckbox(
                  value: paid,
                  onChanged: (v) => macosSetAttendance(
                    ref,
                    group,
                    meeting,
                    member.peerId,
                    v ? MeetingAttendanceStatus.present : status,
                    contributed: v,
                  ),
                ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sync / settings
// -----------------------------------------------------------------------------

class MacosSyncPage extends ConsumerWidget {
  const MacosSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = ref.watch(ipfsNodeStateProvider).value ?? ref.read(ipfsServiceProvider).state;
    final sync = ref.watch(syncStateProvider).value ?? ref.read(syncManagerProvider).state;
    final counts = ref.watch(syncCountsProvider).value ?? const {};
    final failed = ref.watch(failedTransactionsProvider).value ?? const <q.TransactionData>[];
    final log = ref.watch(syncLogProvider).value ?? const <SyncEvent>[];
    final manager = ref.read(syncManagerProvider);
    final peerId = ref.read(ipfsServiceProvider).peerId;

    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Sync'),
        actions: [
          ToolBarIconButton(
            label: 'Sync now',
            icon: const MacosIcon(CupertinoIcons.arrow_2_circlepath),
            showLabel: false,
            onPressed: sync == SyncState.syncing ? null : () => manager.startManualSync(),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (context, controller) => ListView(
            controller: controller,
            padding: vbankMacPadding,
            children: [
              MacosGroupBox(
                label: 'Network',
                children: [
                  MacosInfoRow('Node', node.name),
                  MacosInfoRow('Sync', sync.name),
                  if (manager.lastSyncTime != null)
                    MacosInfoRow('Last sync', fmtDateTime(manager.lastSyncTime!)),
                  if (manager.lastError != null) MacosInfoRow('Last error', manager.lastError!),
                  if (peerId != null) MacosInfoRow('Peer ID', peerId),
                ],
              ),
              const SizedBox(height: 14),
              MacosGroupBox(
                label: 'Queue',
                children: [
                  MacosInfoRow('Queued', '${counts[q.SyncStatus.queued] ?? 0}'),
                  MacosInfoRow('Syncing', '${counts[q.SyncStatus.syncing] ?? 0}'),
                  MacosInfoRow('Synced', '${counts[q.SyncStatus.synced] ?? 0}'),
                  MacosInfoRow('Failed', '${counts[q.SyncStatus.failed] ?? 0}'),
                ],
              ),
              if (failed.isNotEmpty) ...[
                const SizedBox(height: 14),
                MacosGroupBox(
                  label: 'Failed',
                  children: [
                    for (final t in failed)
                      MacosRow(
                        leading: const MacosIcon(CupertinoIcons.exclamationmark_triangle),
                        title: Text('${t.type} ${fmtMoney(t.currency, t.amount)}'),
                        subtitle: Text(t.lastSyncError ?? 'Unknown error'),
                        trailing: PushButton(
                          controlSize: ControlSize.small,
                          onPressed: () async {
                            await ref.read(transactionServiceProvider).retry(t.id);
                            await manager.startManualSync();
                            ref.invalidate(failedTransactionsProvider);
                            ref.invalidate(syncCountsProvider);
                          },
                          child: const Text('Retry'),
                        ),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 14),
              MacosGroupBox(
                label: 'Activity log',
                children: log.isEmpty
                    ? [const Padding(padding: EdgeInsets.all(14), child: Text('Nothing yet'))]
                    : [
                        for (final e in log.take(100))
                          MacosListTile(
                            leading: MacosIcon(
                              switch (e.type) {
                                SyncEventType.error => CupertinoIcons.exclamationmark_circle,
                                SyncEventType.warning => CupertinoIcons.exclamationmark_triangle,
                                _ => CupertinoIcons.checkmark_circle,
                              },
                              color: switch (e.type) {
                                SyncEventType.error => MacosColors.systemRedColor,
                                SyncEventType.warning => MacosColors.systemOrangeColor,
                                _ => null,
                              },
                            ),
                            title: Text(e.message),
                            subtitle: Text(fmtDateTime(e.timestamp)),
                          ),
                      ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class MacosSettingsPage extends ConsumerStatefulWidget {
  const MacosSettingsPage({super.key});

  @override
  ConsumerState<MacosSettingsPage> createState() => _MacosSettingsPageState();
}

class _MacosSettingsPageState extends ConsumerState<MacosSettingsPage> {
  final _service = BackupService();
  List<AppBackup> _backups = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final list = await _service.getAllBackups();
    if (mounted) setState(() => _backups = list);
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(authProvider).identity;
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);

    Widget toggle(String label, bool value, String key, {bool enabled = true}) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(children: [
            Expanded(child: Text(label)),
            MacosSwitch(value: value, onChanged: enabled ? (v) => notifier.set(key, v) : null),
          ]),
        );

    return MacosScaffold(
      toolBar: const ToolBar(title: Text('Settings')),
      children: [
        ContentArea(
          builder: (context, controller) => ListView(
            controller: controller,
            padding: vbankMacPadding,
            children: [
              MacosGroupBox(
                label: 'Identity',
                children: [
                  MacosListTile(
                    leading: const MacosIcon(CupertinoIcons.person_crop_circle),
                    title: Text(identity?.displayName ?? 'Not signed in'),
                    subtitle: Text(identity?.peerId ?? ''),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              MacosGroupBox(
                label: 'Notifications',
                children: [
                  toggle('Enable notifications', prefs.enabled, SettingKeys.notificationsEnabled),
                  toggle('Meeting reminders', prefs.meetings, SettingKeys.notifyMeetings,
                      enabled: prefs.enabled),
                  toggle('Contribution due', prefs.contributions, SettingKeys.notifyContributions,
                      enabled: prefs.enabled),
                  toggle('Loan repayments', prefs.loans, SettingKeys.notifyLoans, enabled: prefs.enabled),
                  toggle('Group activity', prefs.activity, SettingKeys.notifyActivity,
                      enabled: prefs.enabled),
                ],
              ),
              const SizedBox(height: 14),
              MacosGroupBox(
                label: 'Backups',
                children: [
                  MacosRow(
                    leading: const MacosIcon(CupertinoIcons.lock_shield),
                    title: const Text('Create a backup'),
                    subtitle: const Text('Identity, signing key, groups and group keys, encrypted with a PIN'),
                    trailing: PushButton(
                      controlSize: ControlSize.small,
                      onPressed: () async {
                        await macosCreateBackup(context, ref, _service);
                        await _load();
                      },
                      child: const Text('Create'),
                    ),
                  ),
                  for (final b in _backups)
                    MacosRow(
                      leading: const MacosIcon(CupertinoIcons.lock),
                      title: Text(fmtDateTime(b.createdAt)),
                      subtitle: Text('${(b.encryptedPayload.length / 1024).toStringAsFixed(1)} KB · encrypted'),
                      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                        PushButton(
                          controlSize: ControlSize.small,
                          secondary: true,
                          onPressed: () async {
                            try {
                              final file = await _service.exportBackupToFile(b.id);
                              if (context.mounted) await macosToast(context, 'Written to ${file.path}');
                            } catch (e) {
                              if (context.mounted) await macosToast(context, 'Export failed: $e', error: true);
                            }
                          },
                          child: const Text('Export'),
                        ),
                        const SizedBox(width: 6),
                        PushButton(
                          controlSize: ControlSize.small,
                          secondary: true,
                          onPressed: () async {
                            final ok = await macosConfirm(
                              context,
                              title: 'Delete backup?',
                              message: 'This cannot be undone. Exported copies are unaffected.',
                              confirmLabel: 'Delete',
                              destructive: true,
                            );
                            if (!ok) return;
                            await _service.deleteBackup(b.id);
                            await _load();
                          },
                          child: const Text('Delete'),
                        ),
                      ]),
                    ),
                ],
              ),
              const SizedBox(height: 20),
              Align(
                alignment: Alignment.centerLeft,
                child: PushButton(
                  controlSize: ControlSize.large,
                  color: MacosColors.systemRedColor,
                  onPressed: () async {
                    final ok = await macosConfirm(
                      context,
                      title: 'Log out?',
                      message: 'This removes your identity and keys from this Mac. Without an exported '
                          'backup you cannot sign as this identity again.',
                      confirmLabel: 'Log out',
                      destructive: true,
                    );
                    if (ok) await ref.read(authProvider.notifier).logout();
                  },
                  child: const Text('Log out'),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
