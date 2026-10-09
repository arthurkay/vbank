import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/balance.dart';
import '../../domain/group.dart';
import '../../domain/loans.dart';
import '../../domain/meetings.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../member/member_actions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import '../providers/ledger.dart';
import 'group_settings_screen.dart';
import 'create_group_screen.dart';
import 'invites_screen.dart';
import 'loans_screen.dart';
import 'member_detail_screen.dart';
import 'report_screen.dart';
import 'meetings_screen.dart';
import 'record_screen.dart';
import 'sheets.dart';
import 'sync_status_screen.dart';
import 'transaction_detail_screen.dart';
import 'format.dart';
import 'vbank_theme.dart';

/// One group's books: fund stats, balances, members and ledger, plus a
/// record button for treasurers. Opening selects the group; the back
/// button deselects it.
final class MobileGroupDetailScreen extends ConsumerStatefulWidget {
  /// The open group.
  final String groupId;

  /// Creates the detail screen.
  const MobileGroupDetailScreen({super.key, required this.groupId});

  @override
  ConsumerState<MobileGroupDetailScreen> createState() =>
      _MobileGroupDetailState();
}

final class _MobileGroupDetailState
    extends ConsumerState<MobileGroupDetailScreen> {
  /// Active bottom-nav tab: 0 overview, 1 activity, 2 loans, 3 meetings,
  /// 4 more. Local state: leaving and returning resets to overview.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    Future(() {
      if (mounted) {
        ref.read(selectedGroupIdProvider.notifier).state = widget.groupId;
      }
    });
  }

  /// Switches tabs from the bottom navigation bar.
  void _selectTab(Key? key) {
    final int next = switch (key) {
      const ValueKey<String>('tab-activity') => 1,
      const ValueKey<String>('tab-loans') => 2,
      const ValueKey<String>('tab-meetings') => 3,
      const ValueKey<String>('tab-more') => 4,
      _ => 0,
    };
    if (next != _tab) {
      setState(() => _tab = next);
    }
  }

  /// Pushes a drill-in route with the shared transition.
  Future<void> _push(Widget screen) =>
      Navigator.push(context, VBankTheme.pageRoute<void>(context, screen));

  /// Opens the group switcher: every group with its live fund, plus
  /// creating a new one. Switching never loses local data — groups are
  /// just views over the same ledger.
  Future<void> _openSwitcher(BuildContext context, Group? current) {
    final List<Group> groups =
        ref.read(groupListProvider).valueOrNull ?? const [];
    return showVBankSheet<void>(
      context,
      title: 'Switch group',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final Group g in groups)
            _SwitcherRow(
              group: g,
              selected: g.id == current?.id,
              onSelect: () {
                ref.read(selectedGroupIdProvider.notifier).state = g.id;
                Navigator.pop(context);
              },
            ),
          const Gap(8),
          OutlineButton(
            onPressed: () {
              Navigator.pop(context);
              _push(const MobileCreateGroupScreen());
            },
            child: const Text('New group'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () =>
                  ref.read(selectedGroupIdProvider.notifier).state = null,
            ),
          ],
          title: GestureDetector(
            key: const ValueKey('group-switcher'),
            behavior: HitTestBehavior.opaque,
            onTap: () => _openSwitcher(context, group.valueOrNull),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GroupAvatar(name: group.valueOrNull?.name ?? 'Group'),
                const Gap(8),
                Flexible(
                  child: Text(group.valueOrNull?.name ?? 'Group'),
                ),
                const Gap(4),
                const Icon(LucideIcons.chevronDown, size: 16),
              ],
            ),
          ),
          trailing: [
            if (canRecord(
              group.valueOrNull,
              ref.watch(authProvider).identity?.peerId,
            ))
              IconButton.ghost(
                key: const ValueKey('record-button'),
                icon: const Icon(LucideIcons.plus),
                onPressed: () =>
                    _push(MobileRecordScreen(groupId: widget.groupId)),
              ),
          ],
        ),
      ],
      footers: [
        NavigationBar(
          alignment: NavigationBarAlignment.spaceEvenly,
          labelType: NavigationLabelType.all,
          selectedKey: ValueKey<String>('tab-${_tabName(_tab)}'),
          onSelected: _selectTab,
          children: const [
            NavigationItem(
              key: ValueKey<String>('tab-overview'),
              label: Text('Overview'),
              child: Icon(LucideIcons.layoutDashboard),
            ),
            NavigationItem(
              key: ValueKey<String>('tab-activity'),
              label: Text('Activity'),
              child: Icon(LucideIcons.activity),
            ),
            NavigationItem(
              key: ValueKey<String>('tab-loans'),
              label: Text('Loans'),
              child: Icon(LucideIcons.landmark),
            ),
            NavigationItem(
              key: ValueKey<String>('tab-meetings'),
              label: Text('Meetings'),
              child: Icon(LucideIcons.calendarDays),
            ),
            NavigationItem(
              key: ValueKey<String>('tab-more'),
              label: Text('More'),
              child: Icon(LucideIcons.ellipsis),
            ),
          ],
        ),
      ],
      child: AnimatedSwitcher(
        duration: VBankTheme.fadeDuration,
        child: KeyedSubtree(
          key: ValueKey<String>('body-${_tabName(_tab)}'),
          child: _tabBody(context, group.valueOrNull),
        ),
      ),
    );
  }

  /// Tab name for navigation keys.
  static String _tabName(int tab) => switch (tab) {
    1 => 'activity',
    2 => 'loans',
    3 => 'meetings',
    4 => 'more',
    _ => 'overview',
  };

  /// The active tab body.
  Widget _tabBody(BuildContext context, Group? group) => switch (_tab) {
    1 => ListView(
      padding: const EdgeInsets.all(20),
      children: const [_TransactionSection()],
    ),
    2 => _LoansTab(groupId: widget.groupId),
    3 => _MeetingsTab(groupId: widget.groupId),
    4 => _MoreTab(groupId: widget.groupId, push: _push),
    _ => _OverviewTab(groupId: widget.groupId, group: group, push: _push),
  };
}

/// Avatar tile with the group's initials on a muted panel.
final class _GroupAvatar extends StatelessWidget {
  /// The group named.
  final String name;

  /// Creates the avatar.
  const _GroupAvatar({required this.name});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.muted,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(_initials(name)).small.semiBold,
    );
  }

  /// First letters of the first two words, uppercased.
  static String _initials(String name) {
    final List<String> words = name
        .trim()
        .split(RegExp(r'\s+'))
        .where((String w) => w.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return '?';
    }
    final String first = words.first.substring(0, 1);
    final String second = words.length > 1
        ? words[1].substring(0, 1)
        : '';
    return '$first$second'.toUpperCase();
  }
}

/// One switcher row: avatar, name and live fund, checkmark when current.
final class _SwitcherRow extends ConsumerWidget {
  /// The group offered.
  final Group group;

  /// Whether this group is open.
  final bool selected;

  /// Switches to it.
  final VoidCallback onSelect;

  /// Creates the row.
  const _SwitcherRow({
    required this.group,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final double? available = ref
        .watch(fundProvider(group.id))
        .valueOrNull
        ?.available;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onSelect,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            _GroupAvatar(name: group.name),
            const Gap(12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.name).medium,
                  Text(
                    '${group.memberCount} members'
                    '${available == null ? '' : ' · ${_money(available)} available'}',
                  ).small.muted,
                ],
              ),
            ),
            if (selected) const Icon(LucideIcons.check, size: 18),
          ],
        ),
      ),
    );
  }

  /// Two-decimal money text.
  static String _money(double amount) => amount.toStringAsFixed(2);
}

/// One-tap money moves, Monzo-style: record, request, invite. Only the
/// actions this device may take appear — writers record and invite,
/// every signed-in member can request.
final class _QuickActions extends ConsumerWidget {
  /// The open group, if loaded.
  final Group? group;

  /// Drill-in navigation.
  final Future<void> Function(Widget screen) push;

  /// Creates the row.
  const _QuickActions({required this.group, required this.push});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Group? g = group;
    final String? me = ref.watch(authProvider).identity?.peerId;
    if (g == null || me == null) {
      return const SizedBox.shrink();
    }
    final bool writer = canRecord(g, me);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        if (writer)
          _Action(
            icon: LucideIcons.plus,
            label: 'Record',
            onTap: () => push(MobileRecordScreen(groupId: g.id)),
          ),
        _Action(
          icon: LucideIcons.banknote,
          label: 'Request',
          onTap: () => push(MobileRequestLoanScreen(groupId: g.id)),
        ),
        if (writer)
          _Action(
            icon: LucideIcons.userPlus,
            label: 'Invite',
            onTap: () => push(MobileInvitesScreen(groupId: g.id)),
          ),
      ],
    );
  }
}

/// One circular quick action: icon tile plus label.
final class _Action extends StatelessWidget {
  /// The glyph shown.
  final IconData icon;

  /// The caption below.
  final String label;

  /// What tapping does.
  final VoidCallback onTap;

  /// Creates the action.
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52,
            height: 52,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.muted,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 22),
          ),
          const Gap(4),
          Text(label).small,
        ],
      ),
    );
  }
}

/// Overview: hero fund card, quick actions, balances and roster.
final class _OverviewTab extends ConsumerWidget {
  /// The open group.
  final String groupId;

  /// The group, if loaded.
  final Group? group;

  /// Drill-in navigation.
  final Future<void> Function(Widget screen) push;

  /// Creates the overview tab.
  const _OverviewTab({
    required this.groupId,
    required this.group,
    required this.push,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        const _HeroCard(),
        const Gap(16),
        _QuickActions(group: group, push: push),
        const Gap(8),
        _AttentionCard(groupId: groupId),
        const Gap(16),
        _BorrowCard(groupId: groupId),
        const Gap(16),
        const _BalanceSection(),
        const Gap(16),
        const _MemberSection(),
        const Gap(16),
        _NextMeetingLine(groupId: groupId),
      ],
    );
  }
}

/// What needs a human now: loans awaiting review, defaulted loans and
/// members awaiting approval. Silent when there is nothing to do.
final class _AttentionCard extends ConsumerWidget {
  /// The open group.
  final String groupId;

  /// Creates the card.
  const _AttentionCard({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Group? group = ref.watch(selectedGroupProvider).valueOrNull;
    if (group == null) {
      return const SizedBox.shrink();
    }
    final List<LoanRequest> loans =
        ref.watch(loanListProvider(groupId)).valueOrNull ?? const [];
    final String? me = ref.watch(authProvider).identity?.peerId;
    final MemberRole? role = myRole(group, me);
    final bool writer = role != null && canWrite(role);
    final List<String> items = [];
    if (writer) {
      final int pendingLoans = loans
          .where((LoanRequest l) => l.status == LoanStatus.pending)
          .length;
      if (pendingLoans > 0) {
        items.add(
          '$pendingLoans loan${pendingLoans == 1 ? '' : 's'} awaiting '
          'review — see Loans',
        );
      }
      final int waiting = group.members
          .where((Member m) => m.status == MemberStatus.pending)
          .length;
      if (waiting > 0) {
        items.add(
          '$waiting member${waiting == 1 ? '' : 's'} awaiting approval — '
          'see Settings',
        );
      }
    }
    final int defaulted = loans
        .where((LoanRequest l) => l.status == LoanStatus.defaulted)
        .length;
    if (defaulted > 0) {
      final String verb = defaulted == 1 ? 'needs' : 'need';
      items.add(
        '$defaulted defaulted loan${defaulted == 1 ? '' : 's'} $verb follow-up',
      );
    }
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NEEDS ATTENTION').small.semiBold.muted,
            const Gap(8),
            for (final String item in items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(item).small,
              ),
          ],
        ),
      ),
    );
  }
}

/// What the signed-in member can borrow: their contributions times the
/// group multiplier, next to what the fund actually holds.
final class _BorrowCard extends ConsumerWidget {
  /// The open group.
  final String groupId;

  /// Creates the card.
  const _BorrowCard({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Group? group = ref.watch(selectedGroupProvider).valueOrNull;
    final String? me = ref.watch(authProvider).identity?.peerId;
    if (group == null || me == null) {
      return const SizedBox.shrink();
    }
    final List<Balance> balances =
        ref.watch(balancesProvider(groupId)).valueOrNull ?? const [];
    Balance? mine;
    for (final Balance b in balances) {
      if (b.peerId == me) {
        mine = b;
      }
    }
    final double contributed = mine?.totalContributed ?? 0;
    if (contributed <= 0) {
      return const SizedBox.shrink();
    }
    final GroupFund fund =
        ref.watch(fundProvider(groupId)).valueOrNull ??
        const GroupFund(available: 0, lentOut: 0, interestExpected: 0);
    final double limit = contributed * group.config.maxLoanMultiplier;
    final double capped = limit < fund.available ? limit : fund.available;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('YOU CAN BORROW UP TO').small.semiBold.muted,
            const Gap(8),
            DefaultTextStyle.merge(
              style: const TextStyle(
                fontFeatures: [FontFeature.tabularFigures()],
              ),
              child: Text(_money(capped)).x2Large.bold,
            ),
            const Gap(4),
            Text(
              '${group.config.maxLoanMultiplier}× your '
              '${_money(contributed)} contributions · fund holds '
              '${_money(fund.available)}',
            ).small.muted,
          ],
        ),
      ),
    );
  }

  /// Two-decimal money text.
  static String _money(double amount) => amount.toStringAsFixed(2);
}

/// The next scheduled meeting, so members know when to show up.
final class _NextMeetingLine extends ConsumerWidget {
  /// The open group.
  final String groupId;

  /// Creates the line.
  const _NextMeetingLine({required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final List<Meeting> meetings =
        ref.watch(meetingListProvider(groupId)).valueOrNull ?? const [];
    Meeting? next;
    for (final Meeting m in meetings) {
      if (m.status != MeetingStatus.scheduled) {
        continue;
      }
      if (next == null || m.scheduledAt.isBefore(next.scheduledAt)) {
        next = m;
      }
    }
    if (next == null) {
      return const SizedBox.shrink();
    }
    final Meeting found = next;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('NEXT MEETING').small.semiBold.muted,
            const Gap(8),
            Text(
              '${formatDay(found.scheduledAt)} · '
              '${formatCountdown(found.scheduledAt)}',
            ).medium,
          ],
        ),
      ),
    );
  }
}

/// The hero: one huge available-to-lend figure on a matte card.
final class _HeroCard extends ConsumerWidget {
  /// Creates the hero.
  const _HeroCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? groupId = ref.watch(selectedGroupIdProvider);
    if (groupId == null) {
      return const SizedBox.shrink();
    }
    final AsyncValue<GroupFund> fund = ref.watch(fundProvider(groupId));
    return fund.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Text('Error: $error'),
      data: (GroupFund f) => Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('AVAILABLE TO LEND').small.semiBold.muted,
              const Gap(8),
              DefaultTextStyle.merge(
                style: const TextStyle(
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
                child: Text(_money(f.available)).x3Large.bold,
              ),
              const Gap(4),
              Text(
                'Fund ${_money(f.total)} · ${_money(f.lentOut)} on loan',
              ).small.muted,
            ],
          ),
        ),
      ),
    );
  }

  /// Two-decimal money text (currency formatting lives in settings later).
  static String _money(double amount) => amount.toStringAsFixed(2);
}

/// Loans tab: request action over the shared loan rows.
final class _LoansTab extends StatelessWidget {
  /// The open group.
  final String groupId;

  /// Creates the loans tab.
  const _LoansTab({required this.groupId});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Loans').small.semiBold.muted,
            const Spacer(),
            OutlineButton(
              onPressed: () => Navigator.push(
                context,
                VBankTheme.pageRoute<void>(
                  context,
                  MobileRequestLoanScreen(groupId: groupId),
                ),
              ),
              child: const Text('Request loan'),
            ),
          ],
        ),
        const Gap(8),
        Expanded(child: MobileLoanList(groupId: groupId)),
      ],
    ),
  );
}

/// Meetings tab: schedule action over the shared meeting rows.
final class _MeetingsTab extends StatelessWidget {
  /// The open group.
  final String groupId;

  /// Creates the meetings tab.
  const _MeetingsTab({required this.groupId});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Meetings').small.semiBold.muted,
            const Spacer(),
            OutlineButton(
              onPressed: () => Navigator.push(
                context,
                VBankTheme.pageRoute<void>(
                  context,
                  MobileScheduleScreen(groupId: groupId),
                ),
              ),
              child: const Text('Schedule'),
            ),
          ],
        ),
        const Gap(8),
        Expanded(child: MobileMeetingList(groupId: groupId)),
      ],
    ),
  );
}

/// More tab: invites, reports, sync and owner settings.
final class _MoreTab extends ConsumerWidget {
  /// The open group.
  final String groupId;

  /// Drill-in navigation.
  final Future<void> Function(Widget screen) push;

  /// Creates the more tab.
  const _MoreTab({required this.groupId, required this.push});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Group? g = ref.watch(selectedGroupProvider).valueOrNull;
    final String? me = ref.watch(authProvider).identity?.peerId;
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        OutlineButton(
          onPressed: () => push(MobileInvitesScreen(groupId: groupId)),
          child: const Text('Invites'),
        ),
        const Gap(8),
        OutlineButton(
          key: const ValueKey('reports-button'),
          onPressed: () => push(MobileReportScreen(groupId: groupId)),
          child: const Text('Reports'),
        ),
        const Gap(8),
        OutlineButton(
          key: const ValueKey('sync-button'),
          onPressed: () => push(const MobileSyncStatusScreen()),
          child: const Text('Sync'),
        ),
        const Gap(8),
        if (g != null && myRole(g, me) == MemberRole.owner)
          OutlineButton(
            key: const ValueKey('settings-button'),
            onPressed: () => push(MobileGroupSettingsScreen(groupId: groupId)),
            child: const Text('Settings'),
          ),
      ],
    );
  }
}

/// Every member's snapshot.
final class _BalanceSection extends ConsumerWidget {
  /// Creates the section.
  const _BalanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? groupId = ref.watch(selectedGroupIdProvider);
    if (groupId == null) {
      return const SizedBox.shrink();
    }
    final AsyncValue<List<Balance>> balances = ref.watch(
      balancesProvider(groupId),
    );
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    return balances.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Balance> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Balances').small.semiBold.muted,
          const Gap(8),
          for (final Balance b in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text(_nameOf(group.valueOrNull, b.peerId))),
                  Text(b.netBalance.toStringAsFixed(2)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Roster name or the raw peer id.
  static String _nameOf(Group? group, String peerId) {
    if (group == null) {
      return peerId;
    }
    for (final Member m in group.members) {
      if (m.peerId == peerId) {
        return m.name;
      }
    }
    return peerId;
  }
}

/// Roster with roles.
final class _MemberSection extends ConsumerWidget {
  /// Creates the section.
  const _MemberSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final Group? g = group.valueOrNull;
    if (g == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Members').small.semiBold.muted,
        const Gap(8),
        for (final Member m in g.members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => Navigator.push(
                context,
                VBankTheme.pageRoute<void>(
                  context,
                  MobileMemberDetailScreen(groupId: g.id, peerId: m.peerId),
                ),
              ),
              child: Row(
                children: [
                  Expanded(child: Text(m.name)),
                  Text(m.role.name).xSmall.muted,
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Ledger entries, newest last like the book.
final class _TransactionSection extends ConsumerWidget {
  /// Creates the section.
  const _TransactionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? groupId = ref.watch(selectedGroupIdProvider);
    if (groupId == null) {
      return const SizedBox.shrink();
    }
    final AsyncValue<List<Transaction>> txs = ref.watch(
      transactionsProvider(groupId),
    );
    final Group? group = ref.watch(selectedGroupProvider).valueOrNull;
    return txs.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Transaction> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Transactions').small.semiBold.muted,
          const Gap(8),
          if (list.isEmpty) const Text('No transactions yet').small.muted,
          for (final Transaction t in list)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.push(
                  context,
                  VBankTheme.pageRoute<void>(
                    context,
                    MobileTransactionDetailScreen(
                      groupId: groupId,
                      transactionId: t.id,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    _TypeTile(type: t.type),
                    const Gap(12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(_who(group, t)).medium,
                          Text(
                            '${t.type.name} · ${formatDay(t.timestamp)}',
                          ).small.muted,
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        DefaultTextStyle.merge(
                          style: const TextStyle(
                            fontFeatures: [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                          child: Text(
                            '${_sign(t)}${t.amount}',
                          ).medium,
                        ),
                        Text(t.status.name).xSmall.muted,
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// The member side of a transaction, or the kind when nobody owns it.
  static String _who(Group? group, Transaction t) {
    final String peer = t.fromPeerId == 'group' ? t.toPeerId : t.fromPeerId;
    if (peer == 'group') {
      return t.type.name;
    }
    if (group != null) {
      for (final Member m in group.members) {
        if (m.peerId == peer) {
          return m.name;
        }
      }
    }
    return t.type.name;
  }

  /// Fund direction: money out takes `-`, money in takes `+`.
  static String _sign(Transaction t) => switch (t.type) {
    TransactionType.loan || TransactionType.withdrawal => '-',
    TransactionType.reversal => '',
    _ => '+',
  };
}

/// Leading glyph tile for a transaction kind, on a muted panel.
final class _TypeTile extends StatelessWidget {
  /// The kind drawn.
  final TransactionType type;

  /// Creates the tile.
  const _TypeTile({required this.type});

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: scheme.muted,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(_iconFor(type), size: 18),
    );
  }

  /// Glyph per kind.
  static IconData _iconFor(TransactionType type) => switch (type) {
    TransactionType.contribution => LucideIcons.arrowDownToLine,
    TransactionType.withdrawal => LucideIcons.arrowUpFromLine,
    TransactionType.loan => LucideIcons.landmark,
    TransactionType.repayment => LucideIcons.rotateCcw,
    TransactionType.penalty => LucideIcons.triangleAlert,
    TransactionType.fee => LucideIcons.receipt,
    TransactionType.reversal => LucideIcons.undo2,
  };
}
