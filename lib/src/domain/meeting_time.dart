import 'core/failure.dart';
import 'core/result.dart';

/// A wall-clock time of day: the group's weekly meeting slot.
///
/// Replaces the old `'09:00'` string. The wire format stays `'HH:MM'` (the
/// data layer parses/formats it); in here the hour and minute are always in
/// range, so scheduling code never parses again.
final class MeetingTime {
  /// Hour of day, 0–23.
  final int hour;

  /// Minute of hour, 0–59.
  final int minute;

  /// Creates a validated time; prefer [parse] for strings.
  const MeetingTime({required this.hour, required this.minute})
      : assert(hour >= 0 && hour < 24),
        assert(minute >= 0 && minute < 60);

  /// Parses `'HH:MM'` (both parts exactly two digits).
  static Result<MeetingTime> parse(String raw) {
    final Match? m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(raw);
    if (m == null) {
      return const Err(ValidationFailure('meetingTimeFormat'));
    }
    final int hour = int.parse(m.group(1)!);
    final int minute = int.parse(m.group(2)!);
    if (hour > 23 || minute > 59) {
      return const Err(ValidationFailure('meetingTimeRange'));
    }
    return Ok(MeetingTime(hour: hour, minute: minute));
  }

  /// Formats back to the `'HH:MM'` wire representation.
  String format() =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MeetingTime && hour == other.hour && minute == other.minute;

  @override
  int get hashCode => Object.hash(hour, minute);

  @override
  String toString() => 'MeetingTime(${format()})';
}
