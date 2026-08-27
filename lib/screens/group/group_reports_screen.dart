import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/report.dart';
import '../../models/group.dart';
import '../../providers/group_provider.dart';
import '../../providers/loan_provider.dart' show groupFundProvider;
import '../../providers/transaction_provider.dart' show syncTickProvider;
import '../../models/loan_progress.dart';
import '../../services/report_export_service.dart';
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

  bool _exporting = false;

  Future<void> _export(BuildContext context, Group group, GroupReport report, GroupFund? fund) async {
    final format = await showAppSheet<ReportFormat>(
      context,
      title: 'Export report',
      builder: (context, close) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListRow(
            leading: const Icon(LucideIcons.fileText),
            title: const Text('PDF'),
            subtitle: const Text('Summary and member statements, watermarked'),
            onTap: () => close(ReportFormat.pdf),
          ),
          ListRow(
            leading: const Icon(LucideIcons.sheet),
            title: const Text('Excel'),
            subtitle: const Text('Two sheets you can keep working with'),
            onTap: () => close(ReportFormat.excel),
          ),
        ],
      ),
    );
    if (format == null || !context.mounted || _exporting) return;
    setState(() => _exporting = true);
    try {
      final path = await ReportExportService().export(group: group, report: report, fund: fund, format: format);
      if (context.mounted && !(Platform.isAndroid || Platform.isIOS)) showMessage(context, 'Saved to $path');
    } catch (e) {
      if (context.mounted) showMessage(context, 'Export failed: $e', error: true);
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

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
    final fund = ref.watch(groupFundProvider(group.id)).value;
    final c = group.config.currency;
    final scheme = Theme.of(context).colorScheme;

    return AppPage(
      title: '${group.name} · reports',
      trailing: [
        IconButton.ghost(
          icon: const Icon(LucideIcons.download),
          onPressed: report.value == null ? null : () => _export(context, group, report.value!, fund),
        ),
      ],
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
                HeroCard(
                  body: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Metric(label: 'Group fund', value: fmtMoney(c, fund?.total ?? r.groupFundBalance), large: true),
                      const Gap(18),
                      Row(
                        children: [
                          Expanded(child: Metric(label: 'Available to lend', value: fmtMoney(c, fund?.available ?? 0))),
                          Expanded(
                            child: Metric(label: 'Out on loan', value: fmtMoney(c, fund?.lentOut ?? 0), align: CrossAxisAlignment.end),
                          ),
                        ],
                      ),
                    ],
                  ),
                  footer: Row(
                    children: [
                      Expanded(child: Metric(label: 'Interest still expected', value: fmtMoney(c, fund?.interestExpected ?? 0))),
                    ],
                  ),
                ),
                const SectionTitle('This period'),
                Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
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
