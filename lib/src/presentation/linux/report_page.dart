import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../domain/core/result.dart';
import '../../domain/currency.dart';
import '../../domain/group.dart';
import '../../domain/reports.dart';
import '../providers/groups.dart';
import '../providers/reports.dart';

/// Group analytics in Yaru dress: fund metrics, contributions per
/// member and the member table, over a selectable window.
final class LinuxReportPage extends ConsumerStatefulWidget {
  /// The group reported on.
  final String groupId;

  /// Creates the page.
  const LinuxReportPage({super.key, required this.groupId});

  @override
  ConsumerState<LinuxReportPage> createState() => _LinuxReportPageState();
}

final class _LinuxReportPageState extends ConsumerState<LinuxReportPage> {
  ReportRange _range = ReportRange.quarter;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Result<GroupReport>> report = ref.watch(
      groupReportProvider((groupId: widget.groupId, range: _range)),
    );
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final String currency = group.valueOrNull?.config.currency ?? 'ZMW';
    final Color bars = Theme.of(context).colorScheme.primary;
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Reports'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          DropdownButton<ReportRange>(
            value: _range,
            items: [
              for (final ReportRange range in ReportRange.values)
                DropdownMenuItem(value: range, child: Text(range.label)),
            ],
            onChanged: (ReportRange? range) {
              if (range != null) {
                setState(() => _range = range);
              }
            },
          ),
          const SizedBox(height: 16),
          report.when(
            loading: () =>
                const Center(child: YaruCircularProgressIndicator()),
            error: (Object error, _) => Text('Error: $error'),
            data: (Result<GroupReport> result) => result.isErr
                ? Text('Error: ${result.failure}')
                : _ReportBody(
                    report: result.value,
                    currency: currency,
                    barColor: bars,
                  ),
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

  /// Bar color from the theme.
  final Color barColor;

  /// Creates the body.
  const _ReportBody({
    required this.report,
    required this.currency,
    required this.barColor,
  });

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
        const SizedBox(height: 20),
        const Text('Contributions by member'),
        const SizedBox(height: 8),
        if (charted.isEmpty)
          const Text('No contributions in range.')
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
                          color: barColor,
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
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
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
        const SizedBox(height: 20),
        const Text('Members'),
        const SizedBox(height: 8),
        for (final MemberStatement s in top)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                Expanded(child: Text(s.memberName)),
                Text(
                  _money(s.totalContributed),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
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
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(
              value,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
