import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group.dart';
import '../../models/loan.dart';
import '../../models/transaction.dart';
import '../../models/meeting.dart';
import '../../providers/auth_provider.dart';
import '../../providers/balance_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/role_badge.dart';
import '../../widgets/transaction_tile.dart';
import '../home/home_screen.dart' show txFilters, txHaystack;
import '../loan/loan_detail_screen.dart';
import '../meeting/meeting_detail_screen.dart';
import '../transaction/transaction_detail_screen.dart';

class GroupDetailScreen extends ConsumerStatefulWidget {
  const GroupDetailScreen({super.key});

  @override
  ConsumerState<GroupDetailScreen> createState() => _GroupDetailScreenState();
}

class _GroupDetailScreenState extends ConsumerState<GroupDetailScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    // Always render the freshest copy from the list (snapshots may update it).
    final selected = ref.watch(selectedGroupProvider);
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == selected?.id).firstOrNull ?? selected;
    final canWrite = ref.watch(canWriteProvider);
    final my = ref.watch(myMembershipProvider);

    if (group == null) {
      return const AppPage(title: 'Group', child: EmptyState(icon: LucideIcons.users, title: 'No group selected'));
    }
    final dissolved = group.status == GroupStatus.dissolved;
    final pendingMe = my?.status == MemberStatus.pending;

    return AppPage(
      title: group.name,
      subtitle: Text('${group.memberCount} members${dissolved ? ' · dissolved' : ''}'),
      trailing: [
        if (canWrite && !dissolved)
          IconButton.ghost(icon: const Icon(LucideIcons.userPlus), onPressed: () => Navigator.pushNamed(context, '/invite')),
        IconButton.ghost(icon: const Icon(LucideIcons.chartColumn), onPressed: () => Navigator.pushNamed(context, '/group-reports')),
        IconButton.ghost(icon: const Icon(LucideIcons.settings), onPressed: () => Navigator.pushNamed(context, '/group-settings')),
      ],
      floating: canWrite && !dissolved && !pendingMe
          ? Button.primary(
              onPressed: () => Navigator.pushNamed(context, '/create-transaction'),
              leading: const Icon(LucideIcons.plus),
              child: const Text('Transaction'),
            )
          : null,
      child: pendingMe
          ? const EmptyState(
              icon: LucideIcons.hourglass,
              title: 'Waiting for approval',
              subtitle: 'An admin of this group needs to approve your request. Pull to refresh later.',
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Segmented<int>(
                    scrollable: true,
                    values: const [0, 1, 2, 3, 4],
                    selected: _tab,
                    label: (i) => const ['Overview', 'Transactions', 'Members', 'Loans', 'Meetings'][i],
                    onChanged: (i) => setState(() => _tab = i),
                  ),
                ),
                Expanded(
                  child: IndexedStack(
                    index: _tab,
                    children: [
                      _OverviewTab(group: group),
                      _TransactionsTab(group: group),
                      _MembersTab(group: group),
                      _LoansTab(group: group),
                      _MeetingsTab(group: group),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _OverviewTab extends ConsumerWidget {
  final Group group;
  const _OverviewTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = group.config.currency;
    final me = ref.watch(authProvider).identity?.peerId;
    final myBalance = me == null ? null : ref.watch(balanceProvider((peerId: me, groupId: group.id))).value;
    final fund = ref.watch(groupBalancesProvider(group.id)).value;
    final fundTotal = fund?.fold<double>(0, (s, b) => s + b.netBalance) ?? 0;
    final cfg = group.config;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 96),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (group.status == GroupStatus.dissolved) ...[
            const Alert.destructive(
              leading: Icon(LucideIcons.info),
              content: Text('This group has been dissolved. Records are read-only.'),
            ),
            const Gap(12),
          ],
          Row(
            children: [
              Expanded(child: StatCard(label: 'Group fund', value: fmtMoney(c, fundTotal), primary: true)),
              const Gap(12),
              Expanded(child: StatCard(label: 'My net balance', value: fmtMoney(c, myBalance?.netBalance ?? 0))),
            ],
          ),
          const Gap(12),
          ListRow(
            leading: const Icon(LucideIcons.piggyBank),
            title: Text('${fmtMoney(c, cfg.contributionAmount)} per ${cfg.frequency.name}'),
            subtitle: Text('My contributions: ${fmtMoney(c, myBalance?.totalContributed ?? 0)}').small.muted,
          ),
          ListRow(
            leading: const Icon(LucideIcons.dollarSign),
            title: const Text('Loan terms'),
            subtitle: Text(
              'Up to ${cfg.maxLoanMultiplier}× contributions · ${(cfg.loanInterestRate * 100).toStringAsFixed(0)}% interest · '
              'after ${cfg.minContributionsForLoan} contributions · ${cfg.requireLoanApproval ? 'admin approval' : 'auto-approved'}',
            ).small.muted,
          ),
          ListRow(
            leading: const Icon(LucideIcons.users),
            title: const Text('Members'),
            subtitle: Text('${group.memberCount} active').small.muted,
          ),
        ],
      ),
    );
  }
}

class _TransactionsTab extends ConsumerWidget {
  final Group group;
  const _TransactionsTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txsAsync = ref.watch(transactionListProvider(group.id));
    return txsAsync.when(
      data: (txs) {
        if (txs.isEmpty) return const EmptyState(icon: LucideIcons.receipt, title: 'No transactions yet');
        return FilterableList<Transaction>(
          items: txs,
          filters: txFilters(),
          searchPlaceholder: 'Search transactions',
          searchText: (tx) => txHaystack(tx, group: group),
          builder: (context, visible) => RefreshTrigger(
            onRefresh: () => ref.read(transactionListProvider(group.id).notifier).refresh(),
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
              itemCount: visible.length,
              itemBuilder: (context, index) {
                final tx = visible[index];
                return TransactionTile(
                  transaction: tx,
                  onTap: () => pushScreen(context, TransactionDetailScreen(transaction: tx)),
                );
              },
            ),
          ),
        );
      },
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
    );
  }
}

class _MembersTab extends ConsumerWidget {
  final Group group;
  const _MembersTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = group.members.where((m) => m.status != MemberStatus.removed).toList()
      ..sort((a, b) => a.role.index != b.role.index ? a.role.index.compareTo(b.role.index) : a.name.compareTo(b.name));
    if (members.isEmpty) return const EmptyState(icon: LucideIcons.users, title: 'No members yet');

    return FilterableList<Member>(
      items: members,
      searchPlaceholder: 'Search members',
      searchText: (m) => '${m.name} ${m.role.name} ${m.status.name}',
      filters: [
        FilterOption.all<Member>(),
        FilterOption('Admins', (m) => m.role != MemberRole.member),
        FilterOption('Members', (m) => m.role == MemberRole.member),
        FilterOption('Pending', (m) => m.status == MemberStatus.pending),
        FilterOption('Suspended', (m) => m.status == MemberStatus.suspended),
        FilterOption('With loans', (m) => m.hasOutstandingLoan),
      ],
      builder: (context, visible) => ListView.builder(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final member = visible[index];
        final balance = ref.watch(balanceProvider((peerId: member.peerId, groupId: group.id))).value;
        return ListRow(
          leading: InitialsAvatar(member.name),
          title: Text(member.name),
          subtitle: Text(
            member.status == MemberStatus.active
                ? 'Contributed ${fmtMoney(group.config.currency, balance?.totalContributed ?? 0)}'
                    '${member.hasOutstandingLoan ? ' · has loan' : ''}'
                : member.status.name,
          ).small.muted,
          trailing: RoleBadge(role: member.role.name),
        );
      },
      ),
    );
  }
}

class _LoansTab extends ConsumerWidget {
  final Group group;
  const _LoansTab({required this.group});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final loansAsync = ref.watch(loanListProvider(group.id));
    final c = group.config.currency;
    final dissolved = group.status == GroupStatus.dissolved;
    final scheme = Theme.of(context).colorScheme;

    return loansAsync.when(
      data: (loans) {
        final requestButton = dissolved
            ? null
            : Button.outline(
                onPressed: () => Navigator.pushNamed(context, '/request-loan'),
                leading: const Icon(LucideIcons.fileText),
                child: const Text('Request a loan'),
              );
        if (loans.isEmpty) {
          return EmptyState(icon: LucideIcons.landmark, title: 'No loans', action: requestButton);
        }
        String borrowerOf(LoanRequest l) =>
            group.members.where((m) => m.peerId == l.borrowerPeerId).firstOrNull?.name ?? 'member';
        return FilterableList<LoanRequest>(
          items: loans,
          searchPlaceholder: 'Search loans',
          searchText: (l) =>
              '${borrowerOf(l)} ${l.status.name} ${l.requestedAmount.toStringAsFixed(2)} ${l.termWeeks} weeks ${l.reason ?? ''}',
          filters: [
            FilterOption.all<LoanRequest>(),
            FilterOption('Pending', (l) => l.status == LoanStatus.pending),
            FilterOption('Active', (l) => l.isActive),
            FilterOption('Completed', (l) => l.status == LoanStatus.completed),
            FilterOption('Rejected', (l) => l.status == LoanStatus.rejected || l.status == LoanStatus.defaulted),
          ],
          builder: (context, visible) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            ?requestButton,
            const Gap(12),
            for (final loan in visible)
              ListRow(
                title: Text(
                  '${fmtMoney(c, loan.requestedAmount)} · ${group.members.where((m) => m.peerId == loan.borrowerPeerId).firstOrNull?.name ?? 'member'}',
                ),
                subtitle: Text('${loan.status.name} · ${loan.termWeeks} weeks').small.muted,
                trailing: Icon(
                  switch (loan.status) {
                    LoanStatus.pending => LucideIcons.clock,
                    LoanStatus.rejected || LoanStatus.defaulted => LucideIcons.circleX,
                    LoanStatus.completed => LucideIcons.circleCheck,
                    _ => LucideIcons.landmark,
                  },
                  color: switch (loan.status) {
                    LoanStatus.pending => VBankTheme.warning(context),
                    LoanStatus.rejected || LoanStatus.defaulted => scheme.destructive,
                    _ => scheme.primary,
                  },
                ),
                onTap: () => pushScreen(context, LoanDetailScreen(loanId: loan.id)),
              ),
          ],
          ),
        );
      },
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
    );
  }
}

class _MeetingsTab extends ConsumerWidget {
  final Group group;
  const _MeetingsTab({required this.group});

  Future<void> _schedule(BuildContext context, WidgetRef ref) async {
    final parts = group.config.meetingTime.split(':');
    var date = DateTime.now().add(const Duration(days: 7));
    var time = TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: int.tryParse(parts.last) ?? 0);
    final ok = await showAppSheet<bool>(
      context,
      title: 'Schedule meeting',
      builder: (ctx, close) => StatefulBuilder(
        builder: (ctx, setS) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            LabeledField(
              label: 'Date',
              child: DatePicker(
                value: date,
                mode: PromptMode.dialog,
                dialogTitle: const Text('Meeting date'),
                onChanged: (d) => setS(() => date = d ?? date),
              ),
            ),
            const Gap(16),
            LabeledField(
              label: 'Time',
              child: TimePicker(
                value: time,
                mode: PromptMode.dialog,
                dialogTitle: const Text('Meeting time'),
                onChanged: (t) => setS(() => time = t ?? time),
              ),
            ),
            const Gap(24),
            Button.primary(onPressed: () => close(true), child: const Text('Schedule')),
            const Gap(8),
            OutlineButton(onPressed: () => close(false), child: const Text('Cancel')),
          ],
        ),
      ),
    );
    if (ok != true || !context.mounted) return;
    final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    if (when.isBefore(DateTime.now())) {
      showMessage(context, 'Pick a time in the future', error: true);
      return;
    }
    try {
      await ref.read(meetingListProvider(group.id).notifier).createMeeting(scheduledAt: when);
      if (context.mounted) showMessage(context, 'Meeting scheduled');
    } catch (e) {
      if (context.mounted) showMessage(context, '$e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetingsAsync = ref.watch(meetingListProvider(group.id));
    final canWrite = ref.watch(canWriteProvider) && group.status != GroupStatus.dissolved;
    final scheme = Theme.of(context).colorScheme;

    return meetingsAsync.when(
      data: (meetings) {
        final scheduleButton = canWrite
            ? Button.outline(
                onPressed: () => _schedule(context, ref),
                leading: const Icon(LucideIcons.calendar),
                child: const Text('Schedule meeting'),
              )
            : null;
        if (meetings.isEmpty) {
          return EmptyState(icon: LucideIcons.calendar, title: 'No meetings yet', action: scheduleButton);
        }
        return FilterableList<Meeting>(
          items: meetings,
          searchPlaceholder: 'Search meetings',
          searchText: (m) => '${fmtDateTime(m.scheduledAt)} ${m.status.name} ${m.notes ?? ''}',
          filters: [
            FilterOption.all<Meeting>(),
            FilterOption('Scheduled', (m) => m.status == MeetingStatus.scheduled),
            FilterOption('Completed', (m) => m.status == MeetingStatus.completed),
            FilterOption('Cancelled', (m) => m.status == MeetingStatus.cancelled),
          ],
          builder: (context, visible) => ListView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 96),
          children: [
            ?scheduleButton,
            const Gap(12),
            for (final m in visible)
              ListRow(
                leading: Icon(
                  switch (m.status) {
                    MeetingStatus.completed => LucideIcons.circleCheck,
                    MeetingStatus.cancelled => LucideIcons.calendarX,
                    _ => LucideIcons.calendar,
                  },
                  color: m.status == MeetingStatus.cancelled ? scheme.destructive : scheme.primary,
                ),
                title: Text(fmtDateTime(m.scheduledAt)),
                subtitle: Text(
                  '${m.status.name} · ${m.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length} present'
                  '${m.status == MeetingStatus.completed ? ' · collected ${fmtMoney(group.config.currency, m.totalCollected)}' : ''}',
                ).small.muted,
                trailing: const Icon(LucideIcons.chevronRight),
                onTap: () => pushScreen(context, MeetingDetailScreen(meetingId: m.id)),
              ),
          ],
          ),
        );
      },
      loading: () => const LoadingView(),
      error: (e, _) => ErrorView(e),
    );
  }
}
