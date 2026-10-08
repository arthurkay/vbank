import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../domain/balance.dart';
import '../../domain/group.dart';
import '../../domain/loans.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import '../providers/ledger.dart';
import 'invites_page.dart';
import 'report_page.dart';
import 'loans_page.dart';
import 'meetings_page.dart';
import 'record_page.dart';

/// One group's books on macOS: stats, balances, roster, ledger, record.
final class MacosGroupDetailPage extends ConsumerStatefulWidget {
  /// The open group.
  final String groupId;

  /// Creates the page.
  const MacosGroupDetailPage({super.key, required this.groupId});

  @override
  ConsumerState<MacosGroupDetailPage> createState() =>
      _MacosGroupDetailState();
}

final class _MacosGroupDetailState
    extends ConsumerState<MacosGroupDetailPage> {
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
    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(
          onPressed: () =>
              ref.read(selectedGroupIdProvider.notifier).state = null,
        ),
        title: Text(group.valueOrNull?.name ?? 'Group'),
        actions: [
          ToolBarIconButton(
            key: const ValueKey('record-button'),
            label: 'Record transaction',
            icon: const MacosIcon(CupertinoIcons.add),
            showLabel: false,
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => MacosRecordPage(groupId: widget.groupId),
              ),
            ),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              const _FundStats(),
              const SizedBox(height: 16),
              const _BalanceSection(),
              const SizedBox(height: 16),
              const _MemberSection(),
              const SizedBox(height: 16),
              const _TransactionSection(),
              const SizedBox(height: 16),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        MacosLoansPage(groupId: widget.groupId),
                  ),
                ),
                child: const Text('Loans'),
              ),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        MacosMeetingsPage(groupId: widget.groupId),
                  ),
                ),
                child: const Text('Meetings'),
              ),
              const SizedBox(height: 8),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        MacosInvitesPage(groupId: widget.groupId),
                  ),
                ),
                child: const Text('Invites'),
              ),
              const SizedBox(height: 8),
              PushButton(
                key: const ValueKey('reports-button'),
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: () => Navigator.push(
                  context,
                  CupertinoPageRoute<void>(
                    builder: (_) =>
                        MacosReportPage(groupId: widget.groupId),
                  ),
                ),
                child: const Text('Reports'),
              ),
            ],
          ),
        ),
      ],
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
      loading: () => const Center(child: ProgressCircle()),
      error: (Object error, _) => Text('Error: $error'),
      data: (GroupFund f) => Row(
        children: [
          Expanded(
            child: _Stat(label: 'Fund', value: f.total),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _Stat(label: 'Available', value: f.available),
          ),
          const SizedBox(width: 12),
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
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value.toStringAsFixed(2),
            style: MacosTheme.of(context).typography.title1,
          ),
          Text(label),
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
      loading: () => const Center(child: ProgressCircle()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Balance> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Balances'),
          for (final Balance b in list)
            MacosListTile(
              title: Text(_nameOf(group.valueOrNull, b.peerId)),
              subtitle: Text(b.netBalance.toStringAsFixed(2)),
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
        const Text('Members'),
        for (final Member m in group.members)
          MacosListTile(
            leading: const MacosIcon(CupertinoIcons.person_crop_circle),
            title: Text(m.name),
            subtitle: Text(m.role.name),
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
      loading: () => const Center(child: ProgressCircle()),
      error: (Object error, _) => Text('Error: $error'),
      data: (List<Transaction> list) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Transactions'),
          if (list.isEmpty) const Text('No transactions yet'),
          for (final Transaction t in list)
            MacosListTile(
              title: Text('${t.type.name} · ${t.amount}'),
              subtitle: Text(t.status.name),
            ),
        ],
      ),
    );
  }
}

/// Reads the signed-in identity for authorship.
String? authorOf(WidgetRef ref) =>
    ref.read(authProvider).identity?.peerId;
