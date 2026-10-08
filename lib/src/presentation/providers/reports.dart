import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/result.dart';
import '../../domain/reports.dart';
import '../app_scope.dart';

/// Report window.
enum ReportRange {
  /// Last 30 days.
  month,

  /// Last 90 days.
  quarter,

  /// Everything on record.
  allTime;

  /// Display name.
  String get label => switch (this) {
    ReportRange.month => 'Month',
    ReportRange.quarter => 'Quarter',
    ReportRange.allTime => 'All time',
  };
}

/// Period for [range] ending now.
DateTimePeriod periodFor(ReportRange range, DateTime now) {
  final DateTime end = now.toUtc();
  return switch (range) {
    ReportRange.month => DateTimePeriod(
      start: end.subtract(const Duration(days: 30)),
      end: end,
    ),
    ReportRange.quarter => DateTimePeriod(
      start: end.subtract(const Duration(days: 90)),
      end: end,
    ),
    ReportRange.allTime => DateTimePeriod(
      start: DateTime.utc(2000),
      end: end,
    ),
  };
}

/// Group report arguments.
typedef ReportQuery = ({String groupId, ReportRange range});

/// Now for report windows. Overridden in tests to pin time.
final reportNowProvider = Provider<DateTime>((ref) => DateTime.now());

/// The group report for [ReportQuery], refreshed like any provider.
final groupReportProvider =
    FutureProvider.autoDispose.family<Result<GroupReport>, ReportQuery>((
      ref,
      query,
    ) async {
      final services = ref.watch(appServicesProvider);
      return services.reports.generateGroupReport(
        groupId: query.groupId,
        period: periodFor(query.range, ref.watch(reportNowProvider)),
      );
    });
