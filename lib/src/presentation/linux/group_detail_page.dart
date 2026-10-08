import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../domain/balance.dart';
import '../../domain/group.dart';
import '../../domain/loans.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../member/member_actions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import '../providers/ledger.dart';
import 'invites_page.dart';
import 'member_detail_page.dart';
import 'report_page.dart';
import 'loans_page.dart';
import 'meetings_page.dart';
import 'record_page.dart';

/// One group's books on Linux: stats, balances, roster, ledger, record.
final class LinuxGroupDetailPage extends ConsumerStatefulWidget {
  /// The open group.
  final String groupId;

  /// Creates the page.
  const LinuxGroupDetailPage({super.key, required this.groupId});

  @override
  ConsumerState<LinuxGroupDetailPage> createState() =>
      _LinuxGroupDetailState();
}

final class _LinuxGroupDetailState
    extends ConsumerState<LinuxGroupDetailPage> {
  @override
  void initState() {
    super.initState();
    Future(() {
      if (mounted) {
        ref.read(selectedGroupIdProvider.notifier).state = widget.groupId;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(
          onPressed: () =>
              ref.read(selectedGroupIdProvider.notifier).state = null,
        ),
        title: Text(group.valueOrNull?.name ?? 'Group'),
        actions: [
          if (canRecord(
            group.valueOrNull,
            ref.watch(authProvider).identity?.peerId,
          ))
            IconButton(
              key: const ValueKey('record-button'),
              tooltip: 'Record transaction',
              icon: const Icon(YaruIcons.plus),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => LinuxRecordPage(groupId: widget.groupId),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const _FundStats(),
          const SizedBox(height: 16),
          const _BalanceSection(),
          const SizedBox(height: 16),
          const _MemberSection(),
          const SizedBox(height: 16),
          const _TransactionSection(),
          const SizedBox(height: 16),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LinuxLoansPage(groupId: widget.groupId),
              ),
            ),
            child: const Text('Loans'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LinuxMeetingsPage(groupId: widget.groupId),
              ),
            ),
            child: const Text('Meetings'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LinuxInvitesPage(groupId: widget.groupId),
              ),
            ),
            child: const Text('Invites'),
          ),
          const SizedBox(height: 8),
          OutlinedButton(
            key: const ValueKey('reports-button'),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LinuxReportPage(groupId: widget.groupId),
              ),
            ),
            child: const Text('Reports'),
          ),
        ],
      ),
    );
  }
}

/// Fund totals from the live ledger.
final class _FundStats extends ConsumerWidget {
  /// Creates the stats.
  const _FundStats();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? groupId = ref.watch(selectedGroupIdProvider);
    if (groupId == null) {
      return const SizedBox.shrink();
    }
    final AsyncValue<GroupFund> fund = ref.watch(fundProvider(groupId));
    return fund.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (Object error, _) => Text('Error: $error'),
      data: (GroupFund f) => Row(
        children: [
          Expanded(child: _StatTile('Fund', f.total)),
          const SizedBox(width: 12),
          Expanded(child: _StatTile('Available', f.available)),
          const SizedBox(width: 12),
          Expanded(child: _StatTile('On loan', f.lentOut)),
        ],
      ),
    );
  }
}

/// One fund number.
final class _StatTile extends StatelessWidget {
  /// Label.
  final String label;

  /// Value.
  final double value;

  /// Creates the tile.
  const _StatTile(this.label, this.value);

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.toStringAsFixed(2),
                style: Theme.of(context).textTheme.titleLarge,
              ),
              Text(label),
            ],
          ),
        ),
      );
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
    final AsyncValue<List<Balance>> balances =
        ref.watch(balancesProvider(groupId));
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    return balances.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Balance> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balances',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          for (final Balance b in list)
            YaruListTile(
              title: Text(_nameOf(group.valueOrNull, b.peerId)),
              trailing: Text(b.netBalance.toStringAsFixed(2)),
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
    final Group? group = ref.watch(selectedGroupProvider).valueOrNull;
    if (group == null) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Members',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        for (final Member m in group.members)
          YaruListTile(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => LinuxMemberDetailPage(
                  groupId: group.id,
                  peerId: m.peerId,
                ),
              ),
            ),
            title: Text(m.name),
            trailing: Text(m.role.name),
          ),
      ],
    );
  }
}

/// Ledger entries.
final class _TransactionSection extends ConsumerWidget {
  /// Creates the section.
  const _TransactionSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final String? groupId = ref.watch(selectedGroupIdProvider);
    if (groupId == null) {
      return const SizedBox.shrink();
    }
    final AsyncValue<List<Transaction>> txs =
        ref.watch(transactionsProvider(groupId));
    return txs.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Transaction> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transactions',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (list.isEmpty)
            const Text('No transactions yet'),
          for (final Transaction t in list)
            YaruListTile(
              title: Text('${t.type.name} · ${t.amount}'),
              trailing: Text(t.status.name),
            ),
        ],
      ),
    );
  }
}

/// Reads the signed-in identity for authorship. Kept beside the sections
/// so record pages share one lookup.
String? authorOf(WidgetRef ref) =>
    ref.read(authProvider).identity?.peerId;
