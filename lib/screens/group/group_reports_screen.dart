import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/report.dart';
import '../../providers/group_provider.dart';
import '../../providers/transaction_provider.dart' show syncTickProvider;
import '../../services/report_service.dart';
import '../../ui/ui.dart';

final _reportProvider = FutureProvider.family<GroupReport, ({String groupId, DateTime start, DateTime end})>((ref, p) async {
  ref.watch(syncTickProvider);
  return ReportService().generateGroupReport(
    groupId: p.groupId,
    period: DateTimePeriod(start: p.start, end: p.end),
  );
});

/// DESIGN_PLAN §27 group_reports_screen.
class GroupReportsScreen extends ConsumerStatefulWidget {
  const GroupReportsScreen({super.key});

  @override
  ConsumerState<GroupReportsScreen> createState() => _GroupReportsScreenState();
}

class _GroupReportsScreenState extends ConsumerState<GroupReportsScreen> {
  int _months = 3;
  static const _ranges = [1, 3, 12, 0];
  static String _rangeLabel(int m) => switch (m) { 1 => '1 mo', 3 => '3 mo', 12 => '1 yr', _ => 'All' };

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(selectedGroupProvider);
    if (group == null) {
      return const AppPage(title: 'Reports', child: EmptyState(icon: LucideIcons.chartColumn, title: 'No group selected'));
    }
    // Day-granular bounds: the provider is keyed on them, so a fresh
    // microsecond timestamp on every build would restart the report each frame
    // and the page would never leave its loading state.
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final start = _months == 0 ? DateTime(2000) : DateTime(today.year, today.month - _months, today.day);
    final end = today.add(const Duration(days: 1));
    final report = ref.watch(_reportProvider((groupId: group.id, start: start, end: end)));
    final c = group.config.currency;
    final scheme = Theme.of(context).colorScheme;

    return AppPage(
      title: '${group.name} · reports',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Segmented<int>(
            values: _ranges,
            selected: _months,
            label: _rangeLabel,
            onChanged: (m) => setState(() => _months = m),
          ),
          const Gap(16),
          report.when(
            loading: () => const LoadingView(),
            error: (e, _) => ErrorView(e),
            data: (r) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Group fund').small.muted,
                      Text(fmtMoney(c, r.groupFundBalance)).x2Large.bold,
                      const Gap(8),
                      const Divider(),
                      const Gap(8),
                      InfoRow('Contributions', fmtMoney(c, r.totalContributions)),
                      InfoRow('Loans disbursed', fmtMoney(c, r.totalLoansDisbursed)),
                      InfoRow('Loans repaid', fmtMoney(c, r.totalLoansRepaid)),
                      InfoRow('Penalties', fmtMoney(c, r.totalPenalties)),
                      InfoRow('Meetings', '${r.totalMeetings}'),
                      InfoRow('Transactions', '${r.totalTransactions}'),
                    ],
                  ),
                ),
                const SectionTitle('Member statements'),
                for (final s in r.memberStatements)
                  ListRow(
                    leading: InitialsAvatar(s.memberName),
                    title: Text(s.memberName),
                    subtitle: Text(
                      'Contributed ${fmtMoney(c, s.totalContributed)} · loaned ${fmtMoney(c, s.totalLoaned)} · repaid ${fmtMoney(c, s.totalRepaid)}',
                    ).small.muted,
                    trailing: Text(
                      fmtMoney(c, s.outstandingBalance),
                      style: TextStyle(color: s.outstandingBalance < 0 ? scheme.destructive : null),
                    ).semiBold,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
