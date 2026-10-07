import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/balance.dart';
import '../../domain/group.dart';
import '../../domain/loans.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import '../providers/ledger.dart';
import 'record_page.dart';

/// One group's books on Windows: stats, balances, roster, ledger, record.
final class WindowsGroupDetailPage extends ConsumerStatefulWidget {
  /// The open group.
  final String groupId;

  /// Creates the page.
  const WindowsGroupDetailPage({super.key, required this.groupId});

  @override
  ConsumerState<WindowsGroupDetailPage> createState() =>
      _WindowsGroupDetailState();
}

final class _WindowsGroupDetailState
    extends ConsumerState<WindowsGroupDetailPage> {
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
    return NavigationView(
      titleBar: TitleBar(
        title: Text(group.valueOrNull?.name ?? 'Group'),
      ),
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () =>
                ref.read(selectedGroupIdProvider.notifier).state = null,
          ),
          title: Text(group.valueOrNull?.name ?? 'Group'),
          commandBar: CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                key: const ValueKey('record-button'),
                icon: const Icon(FluentIcons.add),
                label: const Text('Record'),
                onPressed: () => Navigator.push(
                  context,
                  FluentPageRoute<void>(
                    builder: (_) => WindowsRecordPage(groupId: widget.groupId),
                  ),
                ),
              ),
            ],
          ),
        ),
        content: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: const [
            _FundStats(),
            SizedBox(height: 14),
            _BalanceSection(),
            SizedBox(height: 14),
            _MemberSection(),
            SizedBox(height: 14),
            _TransactionSection(),
          ],
        ),
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
      loading: () => const Center(child: ProgressRing()),
      error: (Object error, _) => Text('Error: $error'),
      data: (GroupFund f) => Row(
        children: [
          Expanded(
            child: _Stat(label: 'Fund', value: f.total),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(label: 'Available', value: f.available),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: _Stat(label: 'On loan', value: f.lentOut),
          ),
        ],
      ),
    );
  }
}

/// One fund number.
final class _Stat extends StatelessWidget {
  /// Label.
  final String label;

  /// Value.
  final double value;

  /// Creates the stat.
  const _Stat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                value.toStringAsFixed(2),
                style: FluentTheme.of(context).typography.subtitle,
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
      loading: () => const Center(child: ProgressRing()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Balance> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Balances',
            style: FluentTheme.of(context).typography.subtitle,
          ),
          for (final Balance b in list)
            ListTile(
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
          style: FluentTheme.of(context).typography.subtitle,
        ),
        for (final Member m in group.members)
          ListTile(
            leading: const Icon(FluentIcons.contact, size: 18),
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
      loading: () => const Center(child: ProgressRing()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Transaction> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Transactions',
            style: FluentTheme.of(context).typography.subtitle,
          ),
          if (list.isEmpty) const Text('No transactions yet'),
          for (final Transaction t in list)
            ListTile(
              title: Text('${t.type.name} · ${t.amount}'),
              trailing: Text(t.status.name),
            ),
        ],
      ),
    );
  }
}

/// Reads the signed-in identity for authorship.
String? authorOf(WidgetRef ref) =>
    ref.read(authProvider).identity?.peerId;
