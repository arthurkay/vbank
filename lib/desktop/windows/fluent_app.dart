/// The Windows shell: Fluent design.
///
/// A [NavigationView] with a left [NavigationPane], [ScaffoldPage]s with a
/// [PageHeader] and [CommandBar], [Card] groups of [ListTile]s, [TabView] for a
/// group's sections, [ContentDialog] for forms and [InfoBar] for feedback.
library;

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_bootstrap.dart';
import '../../core/app_platform.dart';
import '../../core/ipfs/sync_manager.dart';
import '../../core/presentation/list_filters.dart';
import '../../core/storage/settings_dao.dart';
import '../../core/storage/transaction_dao.dart' as q;
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
import 'fluent_actions.dart';
import 'fluent_kit.dart';

class VBankFluentApp extends ConsumerWidget {
  const VBankFluentApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FluentApp(
      title: 'vBank',
      debugShowCheckedModeBanner: false,
      theme: FluentThemeData(brightness: Brightness.light),
      darkTheme: FluentThemeData(brightness: Brightness.dark),
      home: const AppBootstrap(child: _FluentRoot()),
    );
  }
}

class _FluentRoot extends ConsumerWidget {
  const _FluentRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoaded) {
      return const NavigationView(content: Center(child: ProgressRing()));
    }
    if (!auth.isLoggedIn) return const FluentOnboarding();
    return const FluentShell();
  }
}

// -----------------------------------------------------------------------------
// Onboarding
// -----------------------------------------------------------------------------

class FluentOnboarding extends ConsumerWidget {
  const FluentOnboarding({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = FluentTheme.of(context);
    return NavigationView(
      content: ScaffoldPage(
        content: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(FluentIcons.bank, size: 56, color: theme.accentColor),
                const SizedBox(height: 20),
                Text('vBank', style: theme.typography.titleLarge),
                const SizedBox(height: 8),
                Text(
                  'Village banking that works offline. Your group’s books live on this PC and sync '
                  'directly with your members’ devices.',
                  textAlign: TextAlign.center,
                  style: theme.typography.body,
                ),
                const SizedBox(height: 28),
                FilledButton(
                  onPressed: () => fluentCreateIdentity(context, ref),
                  child: const Text('Get started'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Shell
// -----------------------------------------------------------------------------

class FluentShell extends ConsumerStatefulWidget {
  const FluentShell({super.key});

  @override
  ConsumerState<FluentShell> createState() => _FluentShellState();
}

class _FluentShellState extends ConsumerState<FluentShell> {
  int _index = 0;
  String? _openGroupId;

  @override
  Widget build(BuildContext context) {
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];
    final open = groups.where((g) => g.id == _openGroupId).firstOrNull;
    final node = ref.watch(ipfsNodeStateProvider).value;
    final sync = ref.watch(syncStateProvider).value;

    if (open != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(selectedGroupProvider)?.id != open.id) {
          ref.read(selectedGroupProvider.notifier).state = open;
        }
      });
    }

    return NavigationView(
      titleBar: const TitleBar(title: Text('vBank')),
      pane: NavigationPane(
        selected: _index,
        onChanged: (i) => setState(() {
          _index = i;
          _openGroupId = null;
        }),
        displayMode: PaneDisplayMode.auto,
        items: [
          PaneItem(
            icon: const Icon(FluentIcons.group),
            title: const Text('Groups'),
            body: open == null
                ? FluentGroupsPage(onOpen: (id) => setState(() => _openGroupId = id))
                : FluentGroupPage(group: open, onBack: () => setState(() => _openGroupId = null)),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.bulleted_list),
            title: const Text('Activity'),
            body: const FluentActivityPage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.calendar),
            title: const Text('Meetings'),
            body: const FluentMeetingsPage(),
          ),
          PaneItem(
            icon: const Icon(FluentIcons.sync),
            title: const Text('Sync'),
            infoBadge: sync == SyncState.error ? const InfoBadge(source: Icon(FluentIcons.error)) : null,
            body: const FluentSyncPage(),
          ),
        ],
        footerItems: [
          PaneItem(
            icon: const Icon(FluentIcons.settings),
            title: const Text('Settings'),
            body: const FluentSettingsPage(),
          ),
          PaneItemHeader(
            header: Text(
              '${node?.name ?? 'starting'} · ${sync?.name ?? 'idle'}',
              style: FluentTheme.of(context).typography.caption,
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

class FluentGroupsPage extends ConsumerWidget {
  final ValueChanged<String> onOpen;
  const FluentGroupsPage({super.key, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupsAsync = ref.watch(groupListProvider);

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Groups'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: const Text('New group'),
              onPressed: () => fluentCreateGroup(context, ref),
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.download),
              label: const Text('Join a group'),
              onPressed: () => fluentJoinGroup(context, ref),
            ),
          ],
        ),
      ),
      content: groupsAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => FluentEmpty(icon: FluentIcons.error, title: 'Could not load groups', subtitle: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return FluentEmpty(
              icon: FluentIcons.group,
              title: 'No groups yet',
              subtitle: 'Create a savings group, or join one with an invite link.',
              action: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => fluentCreateGroup(context, ref),
                    child: const Text('New group'),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () => fluentJoinGroup(context, ref),
                    child: const Text('Join a group'),
                  ),
                ],
              ),
            );
          }
          return FluentFilteredList<Group>(
            items: list,
            searchHint: 'Search groups',
            searchText: groupHaystack,
            builder: (context, visible) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: visible.length,
              itemBuilder: (context, i) => _FluentGroupRow(group: visible[i], onOpen: onOpen),
            ),
          );
        },
      ),
    );
  }
}

class _FluentGroupRow extends ConsumerWidget {
  final Group group;
  final ValueChanged<String> onOpen;
  const _FluentGroupRow({required this.group, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(groupBalancesProvider(group.id)).value;
    final fund = balances?.fold<double>(0, (sum, b) => sum + b.netBalance) ?? 0;
    final pending = group.members.where((m) => m.status == MemberStatus.pending).length;

    return Card(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: const Icon(FluentIcons.group, size: 18),
        title: Text(group.name),
        subtitle: Text([
          '${group.memberCount} members',
          '${fmtMoney(group.config.currency, group.config.contributionAmount)} ${group.config.frequency.name}',
          'fund ${fmtMoney(group.config.currency, fund)}',
          if (pending > 0) '$pending awaiting approval',
          if (group.status == GroupStatus.dissolved) 'dissolved',
        ].join(' · ')),
        trailing: const Icon(FluentIcons.chevron_right, size: 12),
        onPressed: () => onOpen(group.id),
      ),
    );
  }
}

class FluentGroupPage extends ConsumerStatefulWidget {
  final Group group;
  final VoidCallback onBack;
  const FluentGroupPage({super.key, required this.group, required this.onBack});

  @override
  ConsumerState<FluentGroupPage> createState() => _FluentGroupPageState();
}

class _FluentGroupPageState extends ConsumerState<FluentGroupPage> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final canWrite = ref.watch(canWriteProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final my = ref.watch(myMembershipProvider);
    final dissolved = group.status == GroupStatus.dissolved;
    final pendingMe = my?.status == MemberStatus.pending;

    return ScaffoldPage(
      header: PageHeader(
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: widget.onBack,
        ),
        title: Text(group.name),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            if (canWrite && !dissolved)
              CommandBarButton(
                icon: const Icon(FluentIcons.add_friend),
                label: const Text('Invite'),
                onPressed: () => fluentShowInvite(context, ref, group),
              ),
            if (canWrite && !dissolved)
              CommandBarButton(
                icon: const Icon(FluentIcons.settings),
                label: const Text('Configuration'),
                onPressed: () => fluentEditGroupConfig(context, ref, group),
              ),
            if (isOwner && !dissolved)
              CommandBarButton(
                icon: const Icon(FluentIcons.delete),
                label: const Text('Dissolve'),
                onPressed: () => fluentDissolveGroup(context, ref, group),
              ),
          ],
        ),
      ),
      content: pendingMe
          ? const FluentEmpty(
              icon: FluentIcons.clock,
              title: 'Waiting for approval',
              subtitle: 'An admin of this group needs to approve your request.',
            )
          : TabView(
              currentIndex: _tab,
              onChanged: (i) => setState(() => _tab = i),
              closeButtonVisibility: CloseButtonVisibilityMode.never,
              tabs: [
                Tab(text: const Text('Overview'), body: _FluentOverview(group: group)),
                Tab(text: const Text('Transactions'), body: _FluentTransactions(group: group)),
                Tab(text: const Text('Members'), body: _FluentMembers(group: group)),
                Tab(text: const Text('Loans'), body: _FluentLoans(group: group)),
                Tab(text: const Text('Meetings'), body: _FluentMeetings(group: group)),
              ],
            ),
    );
  }
}

class _FluentOverview extends ConsumerWidget {
  final Group group;
  const _FluentOverview({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = group.config;
    final me = ref.watch(authProvider).identity?.peerId;
    final mine = me == null ? null : ref.watch(balanceProvider((peerId: me, groupId: group.id))).value;
    final balances = ref.watch(groupBalancesProvider(group.id)).value;
    final fund = balances?.fold<double>(0, (sum, b) => sum + b.netBalance) ?? 0;
    final canWrite = ref.watch(canWriteProvider);
    final dissolved = group.status == GroupStatus.dissolved;

    return ListView(
      padding: vbankFluentPadding,
      children: [
        if (dissolved) ...[
          InfoBar(
            title: const Text('Dissolved'),
            content: const Text('This group has been dissolved. Its records are read-only.'),
            severity: InfoBarSeverity.warning,
          ),
          const SizedBox(height: 12),
        ],
        Row(children: [
          Expanded(
            child: FluentStatTile(
                label: 'Group fund', value: fmtMoney(cfg.currency, fund), emphasise: true),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FluentStatTile(
                label: 'My net balance', value: fmtMoney(cfg.currency, mine?.netBalance ?? 0)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: FluentStatTile(
                label: 'My contributions', value: fmtMoney(cfg.currency, mine?.totalContributed ?? 0)),
          ),
        ]),
        const SizedBox(height: 14),
        if (!dissolved)
          Row(children: [
            if (canWrite)
              FilledButton(
                onPressed: () => fluentRecordTransaction(context, ref, group),
                child: const Text('Record transaction'),
              ),
            const SizedBox(width: 8),
            Button(
              onPressed: () => fluentRequestLoan(context, ref, group),
              child: const Text('Request a loan'),
            ),
            const SizedBox(width: 8),
            if (canWrite)
              Button(
                onPressed: () => fluentScheduleMeeting(context, ref, group),
                child: const Text('Schedule meeting'),
              ),
          ]),
        const SizedBox(height: 14),
        FluentGroup(
          label: 'Group rules',
          children: [
            FluentInfoRow('Contribution',
                '${fmtMoney(cfg.currency, cfg.contributionAmount)} ${cfg.frequency.name}'),
            FluentInfoRow('Loan interest', '${(cfg.loanInterestRate * 100).toStringAsFixed(0)}%'),
            FluentInfoRow('Late penalty', '${(cfg.latePenaltyRate * 100).toStringAsFixed(0)}%'),
            FluentInfoRow('Maximum loan', '${cfg.maxLoanMultiplier}× contributions'),
            FluentInfoRow('Minimum contributions', '${cfg.minContributionsForLoan}'),
            FluentInfoRow('Loan approval', cfg.requireLoanApproval ? 'Admin approval' : 'Automatic'),
            FluentInfoRow('Joining', group.requireApproval ? 'Needs approval' : 'Instant with an invite'),
          ],
        ),
      ],
    );
  }
}

class _FluentTransactions extends ConsumerWidget {
  final Group group;
  const _FluentTransactions({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionListProvider(group.id));
    return txs.when(
      loading: () => const Center(child: ProgressRing()),
      error: (e, _) =>
          FluentEmpty(icon: FluentIcons.error, title: 'Could not load transactions', subtitle: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return const FluentEmpty(
            icon: FluentIcons.bulleted_list,
            title: 'No transactions yet',
            subtitle: 'Admins record contributions, penalties and withdrawals here.',
          );
        }
        return FluentFilteredList<Transaction>(
          items: list,
          filters: transactionFilters(),
          searchHint: 'Search transactions',
          searchText: (tx) => transactionHaystack(tx, group: group),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: visible.length,
            itemBuilder: (context, i) => FluentTransactionRow(transaction: visible[i], group: group),
          ),
        );
      },
    );
  }
}

class FluentTransactionRow extends ConsumerWidget {
  final Transaction transaction;
  final Group? group;
  final bool showGroup;
  const FluentTransactionRow({
    super.key,
    required this.transaction,
    required this.group,
    this.showGroup = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tx = transaction;
    final reversed = tx.status == TransactionStatus.reversed;
    String nameOf(String peerId) => peerId == 'group'
        ? 'Group fund'
        : group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? 'member';

    return Card(
      padding: EdgeInsets.zero,
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        leading: Icon(
          switch (tx.type) {
            TransactionType.contribution => FluentIcons.add,
            TransactionType.loan => FluentIcons.bank,
            TransactionType.repayment => FluentIcons.sync,
            TransactionType.withdrawal => FluentIcons.remove,
            TransactionType.penalty || TransactionType.fee => FluentIcons.warning,
            TransactionType.reversal => FluentIcons.undo,
          },
          size: 16,
        ),
        title: Text(
          '${titleCase(tx.type.name)} · ${fmtMoney(tx.currency, tx.amount)}',
          style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null),
        ),
        subtitle: Text([
          if (showGroup && group != null) group!.name,
          fmtDate(tx.timestamp),
          '${nameOf(tx.fromPeerId)} → ${nameOf(tx.toPeerId)}',
          if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
        ].join(' · ')),
        onPressed: () => _detail(context, ref, nameOf),
      ),
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

    fluentDialog<void>(
      context,
      title: titleCase(tx.type.name),
      width: 520,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          FluentGroup(children: [
            FluentInfoRow('Amount', fmtMoney(tx.currency, tx.amount)),
            FluentInfoRow('Status', titleCase(tx.status.name)),
            FluentInfoRow('From', nameOf(tx.fromPeerId)),
            FluentInfoRow('To', nameOf(tx.toPeerId)),
            FluentInfoRow('Recorded by', nameOf(tx.authorPeerId)),
            FluentInfoRow('When', fmtDateTime(tx.timestamp)),
            if (tx.note != null && tx.note!.isNotEmpty) FluentInfoRow('Note', tx.note!),
            FluentInfoRow('Sequence', '#${tx.sequenceNumber}'),
          ]),
          if (reversals.isNotEmpty) ...[
            const SizedBox(height: 12),
            FluentGroup(
              label: 'Reversals',
              children: [
                for (final r in reversals)
                  ListTile(
                    title: Text('${titleCase(r.status.name)} — ${r.reason}'),
                    subtitle: Text('by ${nameOf(r.requestedByPeerId)}'),
                    trailing: r.isPending && canWrite && r.requestedByPeerId != me
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            Button(
                              onPressed: () {
                                Navigator.pop(context);
                                fluentDecideReversal(context, ref, tx.groupId, r.id, approve: true);
                              },
                              child: const Text('Approve'),
                            ),
                            const SizedBox(width: 6),
                            Button(
                              onPressed: () {
                                Navigator.pop(context);
                                fluentDecideReversal(context, ref, tx.groupId, r.id, approve: false);
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
          Button(
            onPressed: () {
              Navigator.pop(context);
              fluentRequestReversal(context, ref, tx);
            },
            child: const Text('Request reversal'),
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

class _FluentMembers extends ConsumerWidget {
  final Group group;
  const _FluentMembers({required this.group});

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
      return const FluentEmpty(icon: FluentIcons.group, title: 'No members yet');
    }

    return FluentFilteredList<Member>(
      items: members,
      filters: memberFilters(),
      searchHint: 'Search members',
      searchText: memberHaystack,
      builder: (context, visible) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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

          return Card(
            padding: EdgeInsets.zero,
            margin: const EdgeInsets.only(bottom: 6),
            child: ListTile(
              leading: const Icon(FluentIcons.contact, size: 18),
              title: Text('${member.name}${isMe ? ' (you)' : ''}'),
              subtitle: Text([
                titleCase(member.role.name),
                member.status == MemberStatus.active
                    ? 'contributed ${fmtMoney(group.config.currency, balance?.totalContributed ?? 0)}'
                    : member.status.name,
                if (member.hasOutstandingLoan) 'has a loan',
              ].join(' · ')),
              trailing: actions.isEmpty
                  ? null
                  : DropDownButton(
                      leading: const Icon(FluentIcons.more, size: 14),
                      items: [
                        for (final a in actions)
                          MenuFlyoutItem(
                            text: Text(_label(a)),
                            onPressed: () => fluentMemberAction(context, ref, group, member, a),
                          ),
                      ],
                    ),
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

class _FluentLoans extends ConsumerWidget {
  final Group group;
  const _FluentLoans({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loanListProvider(group.id));
    return loans.when(
      loading: () => const Center(child: ProgressRing()),
      error: (e, _) => FluentEmpty(icon: FluentIcons.error, title: 'Could not load loans', subtitle: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return FluentEmpty(
            icon: FluentIcons.bank,
            title: 'No loans yet',
            subtitle: 'Members request loans; admins approve and disburse them.',
            action: FilledButton(
              onPressed: () => fluentRequestLoan(context, ref, group),
              child: const Text('Request a loan'),
            ),
          );
        }
        String borrowerOf(LoanRequest l) =>
            group.members.where((m) => m.peerId == l.borrowerPeerId).firstOrNull?.name ?? 'member';

        return FluentFilteredList<LoanRequest>(
          items: list,
          filters: loanFilters(),
          searchHint: 'Search loans',
          searchText: (l) => loanHaystack(l, borrower: borrowerOf(l)),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final loan = visible[i];
              return Card(
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(FluentIcons.bank, size: 18),
                  title: Text(
                      '${fmtMoney(group.config.currency, loan.requestedAmount)} · ${borrowerOf(loan)}'),
                  subtitle: Text('${titleCase(loan.status.name)} · ${loan.termWeeks} weeks'),
                  trailing: FluentStatusChip(loan.status.name),
                  onPressed: () => Navigator.of(context).push(
                    FluentPageRoute(
                      builder: (_) => FluentLoanDetailPage(groupId: group.id, loanId: loan.id),
                    ),
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

class _FluentMeetings extends ConsumerWidget {
  final Group group;
  const _FluentMeetings({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(meetingListProvider(group.id));
    final canWrite = ref.watch(canWriteProvider) && group.status != GroupStatus.dissolved;

    return meetings.when(
      loading: () => const Center(child: ProgressRing()),
      error: (e, _) => FluentEmpty(icon: FluentIcons.error, title: 'Could not load meetings', subtitle: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return FluentEmpty(
            icon: FluentIcons.calendar,
            title: 'No meetings yet',
            subtitle: 'Schedule the next one before the group leaves.',
            action: canWrite
                ? FilledButton(
                    onPressed: () => fluentScheduleMeeting(context, ref, group),
                    child: const Text('Schedule meeting'),
                  )
                : null,
          );
        }
        return FluentFilteredList<Meeting>(
          items: list,
          filters: meetingFilters(),
          searchHint: 'Search meetings',
          searchText: (m) => meetingHaystack(m),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final m = visible[i];
              final present = m.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
              return Card(
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(FluentIcons.calendar, size: 18),
                  title: Text(fmtDateTime(m.scheduledAt)),
                  subtitle: Text([
                    titleCase(m.status.name),
                    '$present present',
                    if (m.status == MeetingStatus.completed)
                      'collected ${fmtMoney(group.config.currency, m.totalCollected)}',
                  ].join(' · ')),
                  onPressed: () => Navigator.of(context).push(
                    FluentPageRoute(
                      builder: (_) => FluentMeetingDetailPage(groupId: group.id, meetingId: m.id),
                    ),
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

class FluentActivityPage extends ConsumerWidget {
  const FluentActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(allTransactionsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];

    return ScaffoldPage(
      header: const PageHeader(title: Text('Activity')),
      content: txs.when(
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => FluentEmpty(icon: FluentIcons.error, title: 'Could not load activity', subtitle: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return const FluentEmpty(
              icon: FluentIcons.bulleted_list,
              title: 'No transactions yet',
              subtitle: 'Records you and your co-admins make will appear here.',
            );
          }
          Group? groupOf(Transaction tx) => groups.where((g) => g.id == tx.groupId).firstOrNull;
          return FluentFilteredList<Transaction>(
            items: list,
            filters: transactionFilters(),
            searchHint: 'Search activity',
            searchText: (tx) => transactionHaystack(tx, group: groupOf(tx)),
            builder: (context, visible) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: visible.length,
              itemBuilder: (context, i) => FluentTransactionRow(
                transaction: visible[i],
                group: groupOf(visible[i]),
                showGroup: true,
              ),
            ),
          );
        },
      ),
    );
  }
}

class FluentMeetingsPage extends ConsumerWidget {
  const FluentMeetingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(upcomingMeetingsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];

    return ScaffoldPage(
      header: const PageHeader(title: Text('Upcoming meetings')),
      content: meetings.when(
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => FluentEmpty(icon: FluentIcons.error, title: 'Could not load meetings', subtitle: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return const FluentEmpty(
              icon: FluentIcons.calendar,
              title: 'No meetings scheduled',
              subtitle: 'Schedule one from a group’s Meetings tab.',
            );
          }
          String nameOf(Meeting m) => groups.where((g) => g.id == m.groupId).firstOrNull?.name ?? 'Meeting';
          return FluentFilteredList<Meeting>(
            items: list,
            filters: meetingFilters(),
            searchHint: 'Search meetings',
            searchText: (m) => meetingHaystack(m, group: nameOf(m)),
            builder: (context, visible) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final m = visible[i];
                final group = groups.where((g) => g.id == m.groupId).firstOrNull;
                return Card(
                  padding: EdgeInsets.zero,
                  margin: const EdgeInsets.only(bottom: 6),
                  child: ListTile(
                    leading: const Icon(FluentIcons.calendar, size: 18),
                    title: Text(nameOf(m)),
                    subtitle: Text('${fmtDateTime(m.scheduledAt)} · ${m.status.name}'),
                    onPressed: group == null
                        ? null
                        : () {
                            ref.read(selectedGroupProvider.notifier).state = group;
                            Navigator.of(context).push(
                              FluentPageRoute(
                                builder: (_) =>
                                    FluentMeetingDetailPage(groupId: group.id, meetingId: m.id),
                              ),
                            );
                          },
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Loan / meeting detail
// -----------------------------------------------------------------------------

class FluentLoanDetailPage extends ConsumerWidget {
  final String groupId;
  final String loanId;
  const FluentLoanDetailPage({super.key, required this.groupId, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final loanAsync = ref.watch(loanProvider(loanId));
    final scheduleAsync = ref.watch(loanScheduleProvider(loanId));
    final canWrite = ref.watch(canWriteProvider);
    final me = ref.watch(authProvider).identity?.peerId;

    return NavigationView(
      titleBar: const TitleBar(title: Text('Loan')),
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Loan'),
        ),
        content: loanAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => FluentEmpty(icon: FluentIcons.error, title: 'Could not load loan', subtitle: '$e'),
        data: (loan) {
          if (loan == null || group == null) {
            return const FluentEmpty(icon: FluentIcons.bank, title: 'Loan not found');
          }
          final currency = group.config.currency;
          final borrower = group.members.where((m) => m.peerId == loan.borrowerPeerId).firstOrNull;
          final isBorrower = me == loan.borrowerPeerId;
          final schedule = scheduleAsync.value ?? const [];

          return ListView(
            padding: vbankFluentPadding,
            children: [
              Row(children: [
                Text(fmtMoney(currency, loan.requestedAmount),
                    style: FluentTheme.of(context).typography.subtitle),
                const SizedBox(width: 12),
                FluentStatusChip(loan.status.name),
              ]),
              const SizedBox(height: 14),
              FluentGroup(
                label: 'Loan',
                children: [
                  FluentInfoRow('Borrower', borrower?.name ?? loan.borrowerPeerId),
                  FluentInfoRow('Term', '${loan.termWeeks} weeks'),
                  FluentInfoRow('Interest', '${(loan.interestRate * 100).toStringAsFixed(0)}%'),
                  if (loan.approvedAmount > 0)
                    FluentInfoRow('Approved', fmtMoney(currency, loan.approvedAmount)),
                  if (loan.approvedAmount > 0)
                    FluentInfoRow('Total due', fmtMoney(currency, loan.totalWithInterest)),
                  if (loan.reason != null && loan.reason!.isNotEmpty)
                    FluentInfoRow('Reason', loan.reason!),
                  FluentInfoRow('Requested', fmtDateTime(loan.requestedAt)),
                  if (loan.disbursedAt != null)
                    FluentInfoRow('Disbursed', fmtDateTime(loan.disbursedAt!)),
                  if (loan.completedAt != null)
                    FluentInfoRow('Completed', fmtDateTime(loan.completedAt!)),
                ],
              ),
              if (canWrite) ...[
                const SizedBox(height: 14),
                Row(children: [
                  if (loan.status == LoanStatus.pending && !isBorrower) ...[
                    FilledButton(
                      onPressed: () => fluentApproveLoan(context, ref, group, loan),
                      child: const Text('Approve'),
                    ),
                    const SizedBox(width: 8),
                    Button(
                      onPressed: () => fluentRejectLoan(context, ref, group, loan),
                      child: const Text('Reject'),
                    ),
                  ],
                  if (loan.status == LoanStatus.approved)
                    FilledButton(
                      onPressed: () => fluentDisburseLoan(context, ref, group, loan),
                      child: const Text('Record disbursement'),
                    ),
                  if (loan.isActive)
                    FilledButton(
                      onPressed: () => fluentRecordRepayment(context, ref, group, loan, schedule),
                      child: const Text('Record repayment'),
                    ),
                ]),
              ],
              if (schedule.isNotEmpty) ...[
                const SizedBox(height: 14),
                FluentGroup(
                  label: 'Repayment schedule',
                  children: [
                    for (final s in schedule)
                      ListTile(
                        leading: Icon(
                          s.isPaid
                              ? FluentIcons.accept
                              : s.isOverdue
                                  ? FluentIcons.warning
                                  : FluentIcons.clock,
                          size: 16,
                        ),
                        title: Text(
                            'Installment ${s.installmentNumber} — ${fmtMoney(currency, s.expectedAmount)}'),
                        subtitle: Text(
                          'Due ${fmtDate(s.dueDate)}'
                          '${s.paidAmount > 0 ? ' · paid ${s.paidAmount.toStringAsFixed(2)}' : ''}'
                          '${s.penalty > 0 ? ' · penalty ${s.penalty.toStringAsFixed(2)}' : ''}',
                        ),
                        trailing: FluentStatusChip(s.status.name),
                      ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
      ),
    );
  }
}

class FluentMeetingDetailPage extends ConsumerWidget {
  final String groupId;
  final String meetingId;
  const FluentMeetingDetailPage({super.key, required this.groupId, required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final meetingAsync = ref.watch(meetingProvider(meetingId));
    final canWrite = ref.watch(canWriteProvider);

    return NavigationView(
      titleBar: const TitleBar(title: Text('Meeting')),
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: const Text('Meeting'),
        ),
        content: meetingAsync.when(
        loading: () => const Center(child: ProgressRing()),
        error: (e, _) => FluentEmpty(icon: FluentIcons.error, title: 'Could not load meeting', subtitle: '$e'),
        data: (meeting) {
          if (meeting == null || group == null) {
            return const FluentEmpty(icon: FluentIcons.calendar, title: 'Meeting not found');
          }
          final editable = canWrite && meeting.status == MeetingStatus.scheduled;
          final members = group.members.where((m) => m.status == MemberStatus.active).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final present =
              meeting.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
          final contributed = meeting.attendance.where((a) => a.contributed).length;

          return ListView(
            padding: vbankFluentPadding,
            children: [
              Row(children: [
                Text(fmtDateTime(meeting.scheduledAt),
                    style: FluentTheme.of(context).typography.subtitle),
                const SizedBox(width: 12),
                FluentStatusChip(meeting.status.name),
              ]),
              const SizedBox(height: 14),
              FluentGroup(
                label: 'Summary',
                children: [
                  FluentInfoRow('Present', '$present / ${members.length}'),
                  FluentInfoRow('Contributed', '$contributed'),
                  if (meeting.status == MeetingStatus.completed)
                    FluentInfoRow('Collected', fmtMoney(group.config.currency, meeting.totalCollected)),
                  if (meeting.notes != null && meeting.notes!.isNotEmpty)
                    FluentInfoRow('Notes', meeting.notes!),
                ],
              ),
              const SizedBox(height: 14),
              FluentGroup(
                label: 'Attendance',
                children: [
                  for (final m in members)
                    _FluentAttendanceRow(
                      group: group,
                      meeting: meeting,
                      member: m,
                      editable: editable,
                    ),
                ],
              ),
              if (editable) ...[
                const SizedBox(height: 14),
                Row(children: [
                  FilledButton(
                    onPressed: () => fluentCompleteMeeting(context, ref, group, meeting, contributed),
                    child: const Text('Complete meeting'),
                  ),
                  const SizedBox(width: 8),
                  Button(
                    onPressed: () => fluentCancelMeeting(context, ref, group, meeting),
                    child: const Text('Cancel meeting'),
                  ),
                ]),
              ],
            ],
          );
        },
      ),
      ),
    );
  }
}

class _FluentAttendanceRow extends ConsumerWidget {
  final Group group;
  final Meeting meeting;
  final Member member;
  final bool editable;
  const _FluentAttendanceRow({
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

    return ListTile(
      title: Text(member.name),
      subtitle: Text('${titleCase(status.name)}${paid ? ' · contributed' : ''}'),
      trailing: !editable
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ComboBox<MeetingAttendanceStatus>(
                  value: status,
                  items: [
                    for (final s in statuses)
                      ComboBoxItem(value: s, child: Text(titleCase(s.name))),
                  ],
                  onChanged: (s) => fluentSetAttendance(
                    ref,
                    group,
                    meeting,
                    member.peerId,
                    s ?? status,
                    contributed: paid,
                  ),
                ),
                const SizedBox(width: 10),
                Checkbox(
                  checked: paid,
                  content: const Text('Paid'),
                  onChanged: (v) => fluentSetAttendance(
                    ref,
                    group,
                    meeting,
                    member.peerId,
                    v == true ? MeetingAttendanceStatus.present : status,
                    contributed: v ?? false,
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

class FluentSyncPage extends ConsumerWidget {
  const FluentSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = ref.watch(ipfsNodeStateProvider).value ?? ref.read(ipfsServiceProvider).state;
    final sync = ref.watch(syncStateProvider).value ?? ref.read(syncManagerProvider).state;
    final counts = ref.watch(syncCountsProvider).value ?? const {};
    final failed = ref.watch(failedTransactionsProvider).value ?? const <q.TransactionData>[];
    final log = ref.watch(syncLogProvider).value ?? const <SyncEvent>[];
    final manager = ref.read(syncManagerProvider);
    final peerId = ref.read(ipfsServiceProvider).peerId;

    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Sync'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.sync),
              label: const Text('Sync now'),
              onPressed: sync == SyncState.syncing ? null : () => manager.startManualSync(),
            ),
          ],
        ),
      ),
      content: ListView(
        padding: vbankFluentPadding,
        children: [
          FluentGroup(
            label: 'Network',
            children: [
              FluentInfoRow('Node', node.name),
              FluentInfoRow('Sync', sync.name),
              if (manager.lastSyncTime != null)
                FluentInfoRow('Last sync', fmtDateTime(manager.lastSyncTime!)),
              if (manager.lastError != null) FluentInfoRow('Last error', manager.lastError!),
              if (peerId != null) FluentInfoRow('Peer ID', peerId),
            ],
          ),
          const SizedBox(height: 12),
          FluentGroup(
            label: 'Queue',
            children: [
              FluentInfoRow('Queued', '${counts[q.SyncStatus.queued] ?? 0}'),
              FluentInfoRow('Syncing', '${counts[q.SyncStatus.syncing] ?? 0}'),
              FluentInfoRow('Synced', '${counts[q.SyncStatus.synced] ?? 0}'),
              FluentInfoRow('Failed', '${counts[q.SyncStatus.failed] ?? 0}'),
            ],
          ),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 12),
            FluentGroup(
              label: 'Failed',
              children: [
                for (final t in failed)
                  ListTile(
                    leading: const Icon(FluentIcons.warning, size: 16),
                    title: Text('${t.type} ${fmtMoney(t.currency, t.amount)}'),
                    subtitle: Text(t.lastSyncError ?? 'Unknown error'),
                    trailing: Button(
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
          const SizedBox(height: 12),
          FluentGroup(
            label: 'Activity log',
            children: log.isEmpty
                ? [const Padding(padding: EdgeInsets.all(14), child: Text('Nothing yet'))]
                : [
                    for (final e in log.take(100))
                      ListTile(
                        leading: Icon(
                          e.type == SyncEventType.error ? FluentIcons.error : FluentIcons.accept,
                          size: 14,
                        ),
                        title: Text(e.message),
                        subtitle: Text(fmtDateTime(e.timestamp)),
                      ),
                  ],
          ),
        ],
      ),
    );
  }
}

class FluentSettingsPage extends ConsumerStatefulWidget {
  const FluentSettingsPage({super.key});

  @override
  ConsumerState<FluentSettingsPage> createState() => _FluentSettingsPageState();
}

class _FluentSettingsPageState extends ConsumerState<FluentSettingsPage> {
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
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Row(children: [
            Expanded(child: Text(label)),
            ToggleSwitch(checked: value, onChanged: enabled ? (v) => notifier.set(key, v) : null),
          ]),
        );

    return ScaffoldPage(
      header: const PageHeader(title: Text('Settings')),
      content: ListView(
        padding: vbankFluentPadding,
        children: [
          FluentGroup(
            label: 'Identity',
            children: [
              ListTile(
                leading: const Icon(FluentIcons.contact, size: 18),
                title: Text(identity?.displayName ?? 'Not signed in'),
                subtitle: Text(identity?.peerId ?? ''),
              ),
            ],
          ),
          const SizedBox(height: 12),
          FluentGroup(
            label: 'Notifications',
            children: [
              if (!AppPlatform.canNotify)
                const Padding(
                  padding: EdgeInsets.all(14),
                  child: Text(
                    'Desktop notifications are not available on Windows in this build; reminders show '
                    'inside the app instead.',
                  ),
                ),
              toggle('Enable notifications', prefs.enabled, SettingKeys.notificationsEnabled),
              toggle('Meeting reminders', prefs.meetings, SettingKeys.notifyMeetings, enabled: prefs.enabled),
              toggle('Contribution due', prefs.contributions, SettingKeys.notifyContributions,
                  enabled: prefs.enabled),
              toggle('Loan repayments', prefs.loans, SettingKeys.notifyLoans, enabled: prefs.enabled),
              toggle('Group activity', prefs.activity, SettingKeys.notifyActivity, enabled: prefs.enabled),
            ],
          ),
          const SizedBox(height: 12),
          FluentGroup(
            label: 'Backups',
            children: [
              ListTile(
                leading: const Icon(FluentIcons.lock, size: 18),
                title: const Text('Create a backup'),
                subtitle: const Text('Identity, signing key, groups and group keys, encrypted with a PIN'),
                trailing: FilledButton(
                  onPressed: () async {
                    await fluentCreateBackup(context, ref, _service);
                    await _load();
                  },
                  child: const Text('Create'),
                ),
              ),
              for (final b in _backups)
                ListTile(
                  leading: const Icon(FluentIcons.lock, size: 18),
                  title: Text(fmtDateTime(b.createdAt)),
                  subtitle: Text('${(b.encryptedPayload.length / 1024).toStringAsFixed(1)} KB · encrypted'),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    Button(
                      onPressed: () async {
                        try {
                          final file = await _service.exportBackupToFile(b.id);
                          if (context.mounted) fluentInfo(context, 'Written to ${file.path}');
                        } catch (e) {
                          if (context.mounted) fluentInfo(context, 'Export failed: $e', error: true);
                        }
                      },
                      child: const Text('Export'),
                    ),
                    const SizedBox(width: 6),
                    Button(
                      onPressed: () async {
                        final ok = await fluentConfirm(
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
          const SizedBox(height: 18),
          Align(
            alignment: Alignment.centerLeft,
            child: Button(
              onPressed: () async {
                final ok = await fluentConfirm(
                  context,
                  title: 'Log out?',
                  message: 'This removes your identity and keys from this PC. Without an exported backup '
                      'you cannot sign as this identity again.',
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
    );
  }
}
