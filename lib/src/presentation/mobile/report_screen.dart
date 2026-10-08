import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/core/result.dart';
import '../../domain/currency.dart';
import '../../domain/group.dart';
import '../../domain/reports.dart';
import '../providers/groups.dart';
import '../providers/reports.dart';

/// Group analytics in shadcn dress: fund metrics, contributions per
/// member and the member table, over a selectable window.
final class MobileReportScreen extends ConsumerStatefulWidget {
  /// The group reported on.
  final String groupId;

  /// Creates the screen.
  const MobileReportScreen({super.key, required this.groupId});

  @override
  ConsumerState<MobileReportScreen> createState() =>
      _MobileReportScreenState();
}

final class _MobileReportScreenState
    extends ConsumerState<MobileReportScreen> {
  ReportRange _range = ReportRange.quarter;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Result<GroupReport>> report = ref.watch(
      groupReportProvider((groupId: widget.groupId, range: _range)),
    );
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final String currency =
        group.valueOrNull?.config.currency ?? 'ZMW';
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Reports'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final ReportRange range in ReportRange.values)
                range == _range
                    ? PrimaryButton(
                        onPressed: () =>
                            setState(() => _range = range),
                        child: Text(range.label),
                      )
                    : OutlineButton(
                        onPressed: () =>
                            setState(() => _range = range),
                        child: Text(range.label),
                      ),
            ],
          ),
          const Gap(16),
          report.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (Object error, _) =>
                Center(child: Text('Error: $error')),
            data: (Result<GroupReport> result) => result.isErr
                ? Center(child: Text('Error: ${result.failure}'))
                : _ReportBody(report: result.value, currency: currency),
          ),
        ],
      ),
    );
  }
}

/// Metrics, chart and member table for a ready report.
final class _ReportBody extends StatelessWidget {
  /// The generated report.
  final GroupReport report;

  /// ISO currency for amounts.
  final String currency;

  /// Creates the body.
  const _ReportBody({required this.report, required this.currency});

  /// Amounts as `ZK 100.00`.
  String _money(double amount) =>
      CurrencyConfig.supported[currency]?.format(amount) ??
      '$amount $currency';

  @override
  Widget build(BuildContext context) {
    final List<MemberStatement> top = report.memberStatements.toList()
      ..sort((a, b) => b.totalContributed.compareTo(a.totalContributed));
    final List<MemberStatement> charted = top.take(8).toList();
    final double maxY = charted.fold<double>(
      0,
      (m, s) => s.totalContributed > m ? s.totalContributed : m,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _Metric(label: 'Fund', value: _money(report.groupFundBalance)),
            _Metric(
              label: 'Contributed',
              value: _money(report.totalContributions),
            ),
            _Metric(
              label: 'Loans out',
              value: _money(report.totalLoansDisbursed),
            ),
            _Metric(
              label: 'Repaid',
              value: _money(report.totalLoansRepaid),
            ),
          ],
        ),
        const Gap(20),
        Text('Contributions by member').small.semiBold.muted,
        const Gap(8),
        if (charted.isEmpty)
          const Text('No contributions in range.').small
        else
          SizedBox(
            height: 220,
            child: BarChart(
              BarChartData(
                maxY: maxY <= 0 ? 1 : maxY * 1.1,
                barGroups: [
                  for (var i = 0; i < charted.length; i++)
                    BarChartGroupData(
                      x: i,
                      barRods: [
                        BarChartRodData(
                          toY: charted[i].totalContributed,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                ],
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: const AxisTitles(),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      getTitlesWidget: (double value, TitleMeta meta) {
                        final int i = value.toInt();
                        if (i < 0 || i >= charted.length) {
                          return const SizedBox.shrink();
                        }
                        final String name = charted[i].memberName;
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            name.length <= 8 ? name : name.substring(0, 8),
                          ).xSmall.muted,
                        );
                      },
                    ),
                  ),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
              ),
            ),
          ),
        const Gap(20),
        Text('Members').small.semiBold.muted,
        const Gap(8),
        for (final MemberStatement s in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(s.memberName)),
                Text(_money(s.totalContributed)).small.muted,
              ],
            ),
          ),
      ],
    );
  }
}

/// One metric tile.
final class _Metric extends StatelessWidget {
  /// Label above the value.
  final String label;

  /// Formatted value.
  final String value;

  /// Creates the tile.
  const _Metric({required this.label, required this.value});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 150,
    child: Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label).xSmall.muted,
            const Gap(4),
            Text(value).bold,
          ],
        ),
      ),
    ),
  );
}
