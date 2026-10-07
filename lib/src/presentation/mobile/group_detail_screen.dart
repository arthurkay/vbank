import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/balance.dart';
import '../../domain/group.dart';
import '../../domain/loans.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../providers/groups.dart';
import '../providers/ledger.dart';
import 'invites_screen.dart';
import 'loans_screen.dart';
import 'meetings_screen.dart';
import 'record_screen.dart';

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
          title: Text(group.valueOrNull?.name ?? 'Group'),
          trailing: [
            IconButton.ghost(
              key: const ValueKey('record-button'),
              icon: const Icon(LucideIcons.plus),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      MobileRecordScreen(groupId: widget.groupId),
                ),
              ),
            ),
          ],
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const _FundStats(),
          const Gap(16),
          const _BalanceSection(),
          const Gap(16),
          const _MemberSection(),
          const Gap(16),
          const _TransactionSection(),
          const Gap(16),
          OutlineButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => MobileLoansScreen(groupId: widget.groupId),
              ),
            ),
            child: const Text('Loans'),
          ),
          const Gap(8),
          OutlineButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => MobileMeetingsScreen(groupId: widget.groupId),
              ),
            ),
            child: const Text('Meetings'),
          ),
          const Gap(8),
          OutlineButton(
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => MobileInvitesScreen(groupId: widget.groupId),
              ),
            ),
            child: const Text('Invites'),
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Text('Error: $error'),
      data: (GroupFund f) => Row(
        children: [
          Expanded(child: _Stat(label: 'Fund', value: _money(f.total))),
          const Gap(8),
          Expanded(
            child: _Stat(label: 'Available', value: _money(f.available)),
          ),
          const Gap(8),
          Expanded(child: _Stat(label: 'On loan', value: _money(f.lentOut))),
        ],
      ),
    );
  }

  /// Two-decimal money text (currency formatting lives in settings later).
  static String _money(double amount) => amount.toStringAsFixed(2);
}

/// One fund number.
final class _Stat extends StatelessWidget {
  /// Label above the value.
  final String label;

  /// Formatted value.
  final String value;

  /// Creates a stat.
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(value).large.semiBold,
          Text(label).xSmall.muted,
        ],
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
            child: Row(
              children: [
                Expanded(child: Text(m.name)),
                Text(m.role.name).xSmall.muted,
              ],
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
    final AsyncValue<List<Transaction>> txs =
        ref.watch(transactionsProvider(groupId));
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
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(child: Text('${t.type.name} · ${t.amount}')),
                  Text(t.status.name).xSmall.muted,
                ],
              ),
            ),
        ],
      ),
    );
  }
}
