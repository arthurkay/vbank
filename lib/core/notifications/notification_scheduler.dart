import '../storage/notification_schedule_dao.dart';
import '../storage/settings_dao.dart';
import 'notification_service.dart';

/// DESIGN_PLAN §20. All scheduling goes through here so every notification has
/// a stable key (`type:entityId[:n]`), is recorded in `notification_schedules`,
/// and honours the user's preferences.
class NotificationScheduler {
  final NotificationService _service;
  final NotificationScheduleDao _dao;
  final SettingsDao _settings;

  NotificationScheduler(
    this._service, {
    NotificationScheduleDao? dao,
    SettingsDao? settings,
  })  : _dao = dao ?? NotificationScheduleDao(),
        _settings = settings ?? SettingsDao();

  Future<bool> _enabled(String categoryKey) async =>
      await _settings.getBool(SettingKeys.notificationsEnabled) && await _settings.getBool(categoryKey);

  Future<void> _schedule({
    required String key,
    required String type,
    String? groupId,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    if (!at.isAfter(DateTime.now())) return;
    await _service.scheduleNotification(
      id: NotificationService.idFor(key),
      title: title,
      body: body,
      scheduledDate: at,
      payload: groupId,
    );
    await _dao.upsert(id: key, groupId: groupId, type: type, scheduledAt: at, payload: body);
  }

  Future<void> cancel(String key) async {
    await _service.cancelNotification(NotificationService.idFor(key));
    await _dao.deactivate(key);
  }

  Future<void> cancelWithPrefix(String prefix) async {
    for (final key in await _dao.activeIdsWithPrefix(prefix)) {
      await cancel(key);
    }
  }

  // --- meetings ---------------------------------------------------------------

  /// 24h reminder + contribution-due reminder on the morning of the meeting.
  Future<void> scheduleForMeeting({
    required String meetingId,
    required String groupId,
    required String groupName,
    required DateTime meetingTime,
    required double contributionAmount,
    required String currency,
  }) async {
    await cancelWithPrefix('meeting:$meetingId');
    if (await _enabled(SettingKeys.notifyMeetings)) {
      await _schedule(
        key: 'meeting:$meetingId:reminder',
        type: 'meeting_reminder',
        groupId: groupId,
        title: 'Meeting tomorrow',
        body: '$groupName meets in 24 hours',
        at: meetingTime.subtract(const Duration(hours: 24)),
      );
    }
    if (await _enabled(SettingKeys.notifyContributions)) {
      final local = meetingTime.toLocal();
      final morning = DateTime(local.year, local.month, local.day, 8);
      await _schedule(
        key: 'meeting:$meetingId:contribution',
        type: 'contribution_due',
        groupId: groupId,
        title: 'Contribution due today',
        body: '$currency ${contributionAmount.toStringAsFixed(2)} for $groupName',
        at: morning,
      );
    }
  }

  Future<void> cancelForMeeting(String meetingId) => cancelWithPrefix('meeting:$meetingId');

  // --- loans ------------------------------------------------------------------

  /// One "due in 3 days" and one "overdue" notification per installment.
  Future<void> scheduleForLoan({
    required String loanId,
    required String groupId,
    required String groupName,
    required String currency,
    required List<({int number, double amount, DateTime dueDate})> installments,
  }) async {
    await cancelWithPrefix('loan:$loanId');
    if (!await _enabled(SettingKeys.notifyLoans)) return;
    for (final i in installments) {
      await _schedule(
        key: 'loan:$loanId:${i.number}:due',
        type: 'repayment_due',
        groupId: groupId,
        title: 'Repayment due in 3 days',
        body: '$currency ${i.amount.toStringAsFixed(2)} (installment ${i.number}) for $groupName',
        at: i.dueDate.subtract(const Duration(days: 3)),
      );
      await _schedule(
        key: 'loan:$loanId:${i.number}:overdue',
        type: 'repayment_overdue',
        groupId: groupId,
        title: 'Repayment overdue',
        body: 'Installment ${i.number} for $groupName was due today',
        at: i.dueDate,
      );
    }
  }

  Future<void> cancelInstallment(String loanId, int number) async {
    await cancel('loan:$loanId:$number:due');
    await cancel('loan:$loanId:$number:overdue');
  }

  Future<void> cancelForLoan(String loanId) => cancelWithPrefix('loan:$loanId');

  // --- immediate activity -----------------------------------------------------

  Future<void> notifyActivity({
    required String key,
    required String title,
    required String body,
    String? groupId,
    String? payload,
  }) async {
    if (!await _enabled(SettingKeys.notifyActivity)) return;
    await _service.showNotification(
      id: NotificationService.idFor(key),
      title: title,
      body: body,
      payload: payload ?? groupId,
    );
  }

  Future<void> cancelAllReminders() async {
    await _service.cancelAllNotifications();
  }
}
