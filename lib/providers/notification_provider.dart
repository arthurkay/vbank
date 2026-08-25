import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/notifications/notification_scheduler.dart';
import '../core/notifications/notification_service.dart';
import '../core/storage/settings_dao.dart';

final notificationServiceProvider = Provider<NotificationService>((ref) => NotificationService());

final notificationSchedulerProvider = Provider<NotificationScheduler>((ref) {
  return NotificationScheduler(ref.watch(notificationServiceProvider));
});

final settingsDaoProvider = Provider<SettingsDao>((ref) => SettingsDao());

/// Notification preferences (DESIGN_PLAN §20 / notification_settings_screen).
class NotificationPrefs {
  final bool enabled, meetings, contributions, loans, activity;
  const NotificationPrefs({
    this.enabled = true,
    this.meetings = true,
    this.contributions = true,
    this.loans = true,
    this.activity = true,
  });

  NotificationPrefs copyWith({bool? enabled, bool? meetings, bool? contributions, bool? loans, bool? activity}) =>
      NotificationPrefs(
        enabled: enabled ?? this.enabled,
        meetings: meetings ?? this.meetings,
        contributions: contributions ?? this.contributions,
        loans: loans ?? this.loans,
        activity: activity ?? this.activity,
      );
}

class NotificationPrefsNotifier extends StateNotifier<NotificationPrefs> {
  final SettingsDao _dao;
  NotificationPrefsNotifier(this._dao) : super(const NotificationPrefs()) {
    _load();
  }

  Future<void> _load() async {
    state = NotificationPrefs(
      enabled: await _dao.getBool(SettingKeys.notificationsEnabled),
      meetings: await _dao.getBool(SettingKeys.notifyMeetings),
      contributions: await _dao.getBool(SettingKeys.notifyContributions),
      loans: await _dao.getBool(SettingKeys.notifyLoans),
      activity: await _dao.getBool(SettingKeys.notifyActivity),
    );
  }

  Future<void> set(String key, bool value) async {
    await _dao.set(key, value);
    switch (key) {
      case SettingKeys.notificationsEnabled:
        state = state.copyWith(enabled: value);
        break;
      case SettingKeys.notifyMeetings:
        state = state.copyWith(meetings: value);
        break;
      case SettingKeys.notifyContributions:
        state = state.copyWith(contributions: value);
        break;
      case SettingKeys.notifyLoans:
        state = state.copyWith(loans: value);
        break;
      case SettingKeys.notifyActivity:
        state = state.copyWith(activity: value);
        break;
    }
  }
}

final notificationPrefsProvider = StateNotifierProvider<NotificationPrefsNotifier, NotificationPrefs>((ref) {
  return NotificationPrefsNotifier(ref.watch(settingsDaoProvider));
});
