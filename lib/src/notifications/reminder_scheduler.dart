import '../app/group_service.dart';
import '../domain/loans.dart';
import '../domain/meetings.dart';
import '../domain/repositories.dart';
import 'reminder_sink.dart';

/// Refreshes dated reminders for one group: meetings in the next week
/// (24h before) and repayments due in the next three days (1 day
/// before). Every id is deterministic, so refresh re-schedules moved
/// items and cancels spent ones by id reuse.
///
/// Past times never schedule ([ReminderSink] drops them); callers pass
/// UTC `now` (tests pin it).
Future<void> scheduleGroupReminders({
  required GroupService groups,
  required LoanRepository loans,
  required MeetingRepository meetings,
  required ReminderSink sink,
  required String groupId,
  required DateTime now,
}) async {
  final groupResult = await groups.getGroup(groupId);
  final String? groupName = groupResult.isOk ? groupResult.value.name : null;

  final meetingList = await meetings.listByGroup(groupId);
  if (meetingList.isOk) {
    for (final Meeting m in meetingList.value) {
      if (m.status != MeetingStatus.scheduled) {
        continue;
      }
      final DateTime at = m.scheduledAt.toUtc();
      if (at.isBefore(now) || at.isAfter(now.add(const Duration(days: 7)))) {
        continue;
      }
      final int id = _reminderId('meeting', m.id);
      await sink.cancel(id);
      await sink.schedule(
        id: id,
        title: 'Meeting tomorrow${groupName == null ? '' : ' · $groupName'}',
        body: 'Village banking meeting at ${_timeOf(at)}.',
        at: at.subtract(const Duration(days: 1)),
      );
    }
  }

  final loanList = await loans.listByGroup(groupId);
  if (loanList.isErr) {
    return;
  }
  for (final LoanRequest loan in loanList.value) {
    if (loan.status != LoanStatus.disbursed &&
        loan.status != LoanStatus.repaying) {
      continue;
    }
    final schedules = await loans.schedulesByLoan(loan.id);
    if (schedules.isErr) {
      continue;
    }
    for (final schedule in schedules.value) {
      if (schedule.status != RepaymentStatus.pending) {
        continue;
      }
      final DateTime at = schedule.dueDate.toUtc();
      if (at.isBefore(now) || at.isAfter(now.add(const Duration(days: 3)))) {
        continue;
      }
      final int id = _reminderId('repayment', schedule.id);
      await sink.cancel(id);
      await sink.schedule(
        id: id,
        title: 'Repayment due${groupName == null ? '' : ' · $groupName'}',
        body: 'A loan installment is due ${_dayOf(at)}.',
        at: at.subtract(const Duration(days: 1)),
      );
    }
  }
}

/// Stable non-negative id for a reminder kind and record.
int _reminderId(String kind, String id) =>
    Object.hash(kind, id) & 0x7fffffff;

/// `14:30` for a UTC time.
String _timeOf(DateTime at) =>
    '${at.hour.toString().padLeft(2, '0')}:'
    '${at.minute.toString().padLeft(2, '0')}';

/// Weekday name for a UTC date.
String _dayOf(DateTime at) {
  const List<String> days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return days[(at.weekday - 1) % 7];
}
