/// The Linux shell: Ubuntu's Yaru design system.
///
/// Layout follows Ubuntu desktop apps (Settings, App Center): a
/// [YaruMasterDetailPage] whose left pane holds the destinations and whose
/// detail pane holds the page. Inside Groups, selecting a group swaps the pane
/// for the group's own page with a back button and a [YaruTabBar] of sections.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../core/app_bootstrap.dart';
import '../../core/presentation/list_filters.dart';
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
import '../../providers/transaction_provider.dart';
import 'linux_accent.dart';
import 'yaru_actions.dart';
import 'yaru_kit.dart';
import 'yaru_pages.dart';

class VBankYaruApp extends ConsumerStatefulWidget {
  const VBankYaruApp({super.key});

  @override
  ConsumerState<VBankYaruApp> createState() => _VBankYaruAppState();
}

class _VBankYaruAppState extends ConsumerState<VBankYaruApp> {
  final _accent = LinuxAccent();

  @override
  void initState() {
    super.initState();
    _accent.start();
  }

  @override
  void dispose() {
    _accent.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Follow the desktop's accent (Zorin, Pop!_OS, Mint, GNOME 47 accents…)
    // rather than Yaru's Canonical-orange default. When nothing can be read,
    // fall through to Yaru's own variant detection so Ubuntu stays Ubuntu.
    return ValueListenableBuilder<Color?>(
      valueListenable: _accent,
      builder: (context, accent, _) {
        return YaruTheme(
        builder: (context, yaru, child) => MaterialApp(
          scaffoldMessengerKey: yaruMessengerKey,
          title: 'vBank',
          debugShowCheckedModeBanner: false,
          theme: accent == null ? yaru.theme : createYaruLightTheme(primaryColor: accent),
          darkTheme: accent == null ? yaru.darkTheme : createYaruDarkTheme(primaryColor: accent),
          home: const AppBootstrap(child: _YaruRoot()),
        ),
      );
      },
    );
  }
}

class _YaruRoot extends ConsumerWidget {
  const _YaruRoot();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authProvider);
    if (!auth.isLoaded) {
      return const Scaffold(body: Center(child: YaruCircularProgressIndicator()));
    }
    if (!auth.isLoggedIn) return const YaruOnboardingPage();
    return const YaruShell();
  }
}

/// Destinations in the left pane.
enum _Destination { groups, activity, meetings, sync, settings }

class YaruShell extends ConsumerStatefulWidget {
  const YaruShell({super.key});

  @override
  ConsumerState<YaruShell> createState() => _YaruShellState();
}

class _YaruShellState extends ConsumerState<YaruShell> {
  @override
  Widget build(BuildContext context) {
    const destinations = _Destination.values;
    final node = ref.watch(ipfsNodeStateProvider).value;
    final syncState = ref.watch(syncStateProvider).value;

    return YaruMasterDetailPage(
      length: destinations.length,
      tileBuilder: (context, index, selected, availableWidth) {
        final destination = destinations[index];
        final (icon, label) = switch (destination) {
          _Destination.groups => (YaruIcons.users, 'Groups'),
          _Destination.activity => (YaruIcons.book, 'Activity'),
          _Destination.meetings => (YaruIcons.calendar, 'Meetings'),
          _Destination.sync => (YaruIcons.sync, 'Sync'),
          _Destination.settings => (YaruIcons.settings, 'Settings'),
        };
        return YaruMasterTile(
          leading: Icon(icon),
          title: Text(label),
          subtitle: destination == _Destination.sync
              ? Text('${node?.name ?? 'starting'} · ${syncState?.name ?? 'idle'}')
              : null,
          selected: selected,
        );
      },
      pageBuilder: (context, index) => switch (destinations[index]) {
        _Destination.groups => const YaruGroupsPage(),
        _Destination.activity => const YaruActivityPage(),
        _Destination.meetings => const YaruMeetingsPage(),
        _Destination.sync => const YaruSyncPage(),
        _Destination.settings => const YaruSettingsPage(),
      },
    );
  }
}

// -----------------------------------------------------------------------------
// Groups: list, then the selected group's page
// -----------------------------------------------------------------------------

class YaruGroupsPage extends ConsumerStatefulWidget {
  const YaruGroupsPage({super.key});

  @override
  ConsumerState<YaruGroupsPage> createState() => _YaruGroupsPageState();
}

class _YaruGroupsPageState extends ConsumerState<YaruGroupsPage> {
  String? _openGroupId;

  @override
  Widget build(BuildContext context) {
    final groupsAsync = ref.watch(groupListProvider);
    final groups = groupsAsync.value ?? const <Group>[];
    final open = groups.where((g) => g.id == _openGroupId).firstOrNull;

    if (open != null) {
      // Keep the rest of the app (loan pages, dialogs) pointed at this group.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && ref.read(selectedGroupProvider)?.id != open.id) {
          ref.read(selectedGroupProvider.notifier).state = open;
        }
      });
      return YaruGroupPage(
        group: open,
        onBack: () => setState(() => _openGroupId = null),
      );
    }

    return YaruDetailPage(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            tooltip: 'Join a group',
            icon: const Icon(YaruIcons.download),
            onPressed: () => yaruJoinGroup(context, ref),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: FilledButton.icon(
              icon: const Icon(YaruIcons.plus),
              label: const Text('New group'),
              onPressed: () => yaruCreateGroup(context, ref),
            ),
          ),
        ],
      ),
      body: groupsAsync.when(
        loading: () => const Center(child: YaruCircularProgressIndicator()),
        error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load groups', subtitle: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return YaruEmpty(
              icon: YaruIcons.users,
              title: 'No groups yet',
              subtitle: 'Create a savings group, or join one with an invite link.',
              action: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FilledButton(
                    onPressed: () => yaruCreateGroup(context, ref),
                    child: const Text('New group'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: () => yaruJoinGroup(context, ref),
                    child: const Text('Join a group'),
                  ),
                ],
              ),
            );
          }
          return YaruFilteredList<Group>(
            items: list,
            searchHint: 'Search groups',
            searchText: groupHaystack,
            builder: (context, visible) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              itemCount: visible.length,
              itemBuilder: (context, i) => _GroupRow(
                group: visible[i],
                onOpen: () => setState(() => _openGroupId = visible[i].id),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _GroupRow extends ConsumerWidget {
  final Group group;
  final VoidCallback onOpen;
  const _GroupRow({required this.group, required this.onOpen});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final balances = ref.watch(groupBalancesProvider(group.id)).value;
    final fund = balances?.fold<double>(0, (sum, b) => sum + b.netBalance) ?? 0;
    final pending = group.members.where((m) => m.status == MemberStatus.pending).length;

    return YaruListTile(
      leading: CircleAvatar(child: Text(group.name.isEmpty ? '?' : group.name[0].toUpperCase())),
      title: Text(group.name),
      subtitle: Text([
        '${group.memberCount} members',
        '${fmtMoney(group.config.currency, group.config.contributionAmount)} ${group.config.frequency.name}',
        if (pending > 0) '$pending awaiting approval',
        if (group.status == GroupStatus.dissolved) 'dissolved',
      ].join(' · ')),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(fmtMoney(group.config.currency, fund), style: Theme.of(context).textTheme.bodyLarge),
          const SizedBox(width: 12),
          const Icon(YaruIcons.pan_end),
        ],
      ),
      onTap: onOpen,
    );
  }
}

/// One group, with Ubuntu-style tabs for its sections.
class YaruGroupPage extends ConsumerWidget {
  final Group group;
  final VoidCallback onBack;
  const YaruGroupPage({super.key, required this.group, required this.onBack});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canWrite = ref.watch(canWriteProvider);
    final isOwner = ref.watch(isOwnerProvider);
    final my = ref.watch(myMembershipProvider);
    final dissolved = group.status == GroupStatus.dissolved;
    final pendingMe = my?.status == MemberStatus.pending;

    return DefaultTabController(
      length: 5,
      child: YaruDetailPage(
        appBar: AppBar(
          leading: YaruBackButton(onPressed: onBack),
          title: Text(group.name),
          bottom: pendingMe
              ? null
              : const PreferredSize(
                  preferredSize: Size.fromHeight(48),
                  child: YaruTabBar(
                    tabs: [
                      Tab(text: 'Overview'),
                      Tab(text: 'Transactions'),
                      Tab(text: 'Members'),
                      Tab(text: 'Loans'),
                      Tab(text: 'Meetings'),
                    ],
                  ),
                ),
          actions: [
            if (canWrite && !dissolved)
              IconButton(
                tooltip: 'Invite members',
                icon: const Icon(YaruIcons.user_new),
                onPressed: () => yaruShowInvite(context, ref, group),
              ),
            if (canWrite && !dissolved)
              IconButton(
                tooltip: 'Group configuration',
                icon: const Icon(YaruIcons.settings),
                onPressed: () => yaruEditGroupConfig(context, ref, group),
              ),
            if (isOwner && !dissolved)
              IconButton(
                tooltip: 'Dissolve group',
                icon: const Icon(YaruIcons.trash),
                onPressed: () => yaruDissolveGroup(context, ref, group),
              ),
            const SizedBox(width: 8),
          ],
        ),
        body: pendingMe
            ? const YaruEmpty(
                icon: YaruIcons.clock,
                title: 'Waiting for approval',
                subtitle: 'An admin of this group needs to approve your request.',
              )
            : TabBarView(
                children: [
                  _OverviewTab(group: group),
                  _TransactionsTab(group: group),
                  _MembersTab(group: group),
                  _LoansTab(group: group),
                  _MeetingsTab(group: group),
                ],
              ),
      ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  final Group group;
  const _OverviewTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cfg = group.config;
    final me = ref.watch(authProvider).identity?.peerId;
    final mine = me == null ? null : ref.watch(balanceProvider((peerId: me, groupId: group.id))).value;
    final fund = ref.watch(groupFundProvider(group.id)).value;
    final canWrite = ref.watch(canWriteProvider);
    final dissolved = group.status == GroupStatus.dissolved;

    return ListView(
      padding: vbankPagePadding,
      children: [
        if (dissolved) ...[
          YaruBanner(
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text('This group has been dissolved. Its records are read-only.'),
            ),
          ),
          const SizedBox(height: 16),
        ],
        // Where the money is: owned, available to lend, out with borrowers.
        Row(
          children: [
            Expanded(
              child: YaruStatTile(
                label: 'Group fund',
                value: fmtMoney(cfg.currency, fund?.total ?? 0),
                emphasise: true,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: YaruStatTile(
                label: 'Available to lend',
                value: fmtMoney(cfg.currency, fund?.available ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: YaruStatTile(
                label: 'Out on loan',
                value: fmtMoney(cfg.currency, fund?.lentOut ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: YaruStatTile(
                label: 'My net balance',
                value: fmtMoney(cfg.currency, mine?.netBalance ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: YaruStatTile(
                label: 'My contributions',
                value: fmtMoney(cfg.currency, mine?.totalContributed ?? 0),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: YaruStatTile(
                label: 'Interest still expected',
                value: fmtMoney(cfg.currency, fund?.interestExpected ?? 0),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (!dissolved)
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (canWrite)
                FilledButton.icon(
                  icon: const Icon(YaruIcons.plus),
                  label: const Text('Record transaction'),
                  onPressed: () => yaruRecordTransaction(context, ref, group),
                ),
              OutlinedButton.icon(
                icon: const Icon(YaruIcons.book),
                label: const Text('Request a loan'),
                onPressed: () => yaruRequestLoan(context, ref, group),
              ),
              if (canWrite)
                OutlinedButton.icon(
                  icon: const Icon(YaruIcons.calendar),
                  label: const Text('Schedule meeting'),
                  onPressed: () => yaruScheduleMeeting(context, ref, group),
                ),
            ],
          ),
        const SizedBox(height: 16),
        YaruSection(
          headline: const Text('Group rules'),
          child: Column(
            children: [
              YaruInfoRow('Contribution', '${fmtMoney(cfg.currency, cfg.contributionAmount)} ${cfg.frequency.name}'),
              YaruInfoRow('Loan interest', '${(cfg.loanInterestRate * 100).toStringAsFixed(0)}%'),
              YaruInfoRow('Late penalty', '${(cfg.latePenaltyRate * 100).toStringAsFixed(0)}%'),
              YaruInfoRow('Maximum loan', '${cfg.maxLoanMultiplier}× contributions'),
              YaruInfoRow('Minimum contributions', '${cfg.minContributionsForLoan}'),
              YaruInfoRow('Loan approval', cfg.requireLoanApproval ? 'Admin approval' : 'Automatic'),
              YaruInfoRow('Joining', group.requireApproval ? 'Needs approval' : 'Instant with an invite'),
              YaruInfoRow('Members', '${group.memberCount} active'),
            ],
          ),
        ),
      ],
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  final Group group;
  const _TransactionsTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(transactionListProvider(group.id));
    return txs.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load transactions', subtitle: '$e'),
      data: (list) {
        if (list.isEmpty) {
          return const YaruEmpty(
            icon: YaruIcons.book,
            title: 'No transactions yet',
            subtitle: 'Admins record contributions, penalties and withdrawals here.',
          );
        }
        return YaruFilteredList<Transaction>(
          items: list,
          filters: transactionFilters(),
          searchHint: 'Search transactions',
          searchText: (tx) => transactionHaystack(tx, group: group),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: visible.length,
            itemBuilder: (context, i) => YaruTransactionTile(transaction: visible[i], group: group),
          ),
        );
      },
    );
  }
}

class _MembersTab extends ConsumerWidget {
  final Group group;
  const _MembersTab({required this.group});

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
      return const YaruEmpty(icon: YaruIcons.users, title: 'No members yet');
    }

    return YaruFilteredList<Member>(
      items: members,
      filters: memberFilters(),
      searchHint: 'Search members',
      searchText: memberHaystack,
      builder: (context, visible) => ListView.builder(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
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

          return YaruListTile(
            leading: CircleAvatar(
              child: Text(member.name.isEmpty ? '?' : member.name[0].toUpperCase()),
            ),
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
                : PopupMenuButton<String>(
                    icon: const Icon(YaruIcons.view_more_horizontal),
                    itemBuilder: (context) => [
                      for (final a in actions)
                        PopupMenuItem(value: a, child: Text(_actionLabel(a, member))),
                    ],
                    onSelected: (a) => yaruMemberAction(context, ref, group, member, a),
                  ),
          );
        },
      ),
    );
  }

  static String _actionLabel(String action, Member m) => switch (action) {
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

class _LoansTab extends ConsumerWidget {
  final Group group;
  const _LoansTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loans = ref.watch(loanListProvider(group.id));
    final dissolved = group.status == GroupStatus.dissolved;

    return loans.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load loans', subtitle: '$e'),
      data: (list) {
        final request = dissolved
            ? null
            : OutlinedButton.icon(
                icon: const Icon(YaruIcons.plus),
                label: const Text('Request a loan'),
                onPressed: () => yaruRequestLoan(context, ref, group),
              );
        if (list.isEmpty) {
          return YaruEmpty(
            icon: YaruIcons.book,
            title: 'No loans yet',
            subtitle: 'Members request loans; admins approve and disburse them.',
            action: request,
          );
        }
        String borrowerOf(LoanRequest l) =>
            group.members.where((m) => m.peerId == l.borrowerPeerId).firstOrNull?.name ?? 'member';

        return YaruFilteredList<LoanRequest>(
          items: list,
          filters: loanFilters(),
          searchHint: 'Search loans',
          searchText: (l) => loanHaystack(l, borrower: borrowerOf(l)),
          header: request == null
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Align(alignment: Alignment.centerLeft, child: request),
                ),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final loan = visible[i];
              final p = ref.watch(groupLoanProgressProvider(group.id)).value?[loan.id];
              final c = group.config.currency;
              return YaruListTile(
                leading: const Icon(YaruIcons.book),
                title: Text('${fmtMoney(c, p?.borrowed ?? loan.requestedAmount)} · ${borrowerOf(loan)}'),
                subtitle: Text(
                  p != null && p.totalDue > 0
                      ? 'Repaid ${fmtMoney(c, p.repaid)} of ${fmtMoney(c, p.totalDue)} · ${loan.termWeeks} weeks'
                      : '${titleCase(loan.status.name)} · ${loan.termWeeks} weeks',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    YaruStatusChip(loan.status.name),
                    const SizedBox(width: 12),
                    const Icon(YaruIcons.pan_end),
                  ],
                ),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => YaruLoanDetailPage(groupId: group.id, loanId: loan.id),
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

class _MeetingsTab extends ConsumerWidget {
  final Group group;
  const _MeetingsTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(meetingListProvider(group.id));
    final canWrite = ref.watch(canWriteProvider) && group.status != GroupStatus.dissolved;

    return meetings.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load meetings', subtitle: '$e'),
      data: (list) {
        final schedule = canWrite
            ? OutlinedButton.icon(
                icon: const Icon(YaruIcons.calendar),
                label: const Text('Schedule meeting'),
                onPressed: () => yaruScheduleMeeting(context, ref, group),
              )
            : null;
        if (list.isEmpty) {
          return YaruEmpty(
            icon: YaruIcons.calendar,
            title: 'No meetings yet',
            subtitle: 'Schedule the next one before the group leaves.',
            action: schedule,
          );
        }
        return YaruFilteredList<Meeting>(
          items: list,
          filters: meetingFilters(),
          searchHint: 'Search meetings',
          searchText: (m) => meetingHaystack(m),
          header: schedule == null
              ? null
              : Padding(
                  padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
                  child: Align(alignment: Alignment.centerLeft, child: schedule),
                ),
          builder: (context, visible) => ListView.builder(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            itemCount: visible.length,
            itemBuilder: (context, i) {
              final m = visible[i];
              final present = m.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
              return YaruListTile(
                leading: Icon(m.status == MeetingStatus.completed ? YaruIcons.ok : YaruIcons.calendar),
                title: Text(fmtDateTime(m.scheduledAt)),
                subtitle: Text([
                  titleCase(m.status.name),
                  '$present present',
                  if (m.status == MeetingStatus.completed)
                    'collected ${fmtMoney(group.config.currency, m.totalCollected)}',
                ].join(' · ')),
                trailing: const Icon(YaruIcons.pan_end),
                onTap: () => Navigator.of(context, rootNavigator: true).push(
                  MaterialPageRoute(
                    builder: (_) => YaruMeetingDetailPage(groupId: group.id, meetingId: m.id),
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
