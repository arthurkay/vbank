import 'package:fl_chart/fl_chart.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/result.dart';
import '../../domain/currency.dart';
import '../../domain/group.dart';
import '../../domain/reports.dart';
import '../providers/groups.dart';
import '../providers/reports.dart';

/// Group analytics in Fluent dress: fund metrics, contributions per
/// member and the member table, over a selectable window.
final class WindowsReportPage extends ConsumerStatefulWidget {
  /// The group reported on.
  final String groupId;

  /// Creates the page.
  const WindowsReportPage({super.key, required this.groupId});

  @override
  ConsumerState<WindowsReportPage> createState() => _WindowsReportPageState();
}

final class _WindowsReportPageState
    extends ConsumerState<WindowsReportPage> {
  ReportRange _range = ReportRange.quarter;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Result<GroupReport>> report = ref.watch(
      groupReportProvider((groupId: widget.groupId, range: _range)),
    );
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final String currency = group.valueOrNull?.config.currency ?? 'ZMW';
    return NavigationView(
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Reports'),
        ),
        content: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            ComboBox<ReportRange>(
              value: _range,
              items: [
                for (final ReportRange range in ReportRange.values)
                  ComboBoxItem(value: range, child: Text(range.label)),
              ],
              onChanged: (ReportRange? range) {
                if (range != null) {
                  setState(() => _range = range);
                }
              },
            ),
            const SizedBox(height: 16),
            report.when(
              loading: () => const Center(child: ProgressRing()),
              error: (Object error, _) => Text('Error: $error'),
              data: (Result<GroupReport> result) => result.isErr
                  ? Text('Error: ${result.failure}')
                  : _ReportBody(
                      report: result.value,
                      currency: currency,
                    ),
            ),
          ],
        ),
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
    final Color bars = FluentTheme.of(context).accentColor;
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
                          color: bars,
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
                Text(_money(s.totalContributed)),
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
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [Text(label), const SizedBox(height: 4), Text(value)],
      ),
    ),
  );
}
