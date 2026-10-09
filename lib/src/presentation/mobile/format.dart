/// Human date and time words shared by mobile screens: short day labels
/// (`5 Oct 2026`) and countdowns (`in 3 d`). Pure functions of their
/// inputs, so widget tests stay deterministic.
library;

/// Short day label for timestamps: `5 Oct 2026`.
String formatDay(DateTime at) {
  final DateTime local = at.toLocal();
  return '${local.day} ${_monthName(local.month)} ${local.year}';
}

/// Countdown to [at] from now: `in 3 d`, `Today`, or `Due date passed`.
String formatCountdown(DateTime at) {
  final Duration left = at.difference(DateTime.now());
  if (left.isNegative) {
    return 'Due date passed';
  }
  if (left.inDays > 0) {
    return 'In ${left.inDays} d';
  }
  return 'Today';
}

/// Three-letter month name.
String _monthName(int month) => const [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
][month - 1];
