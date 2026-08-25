import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/storage/settings_dao.dart';
import '../../providers/notification_provider.dart';
import '../../ui/ui.dart';

class NotificationSettingsScreen extends ConsumerWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prefs = ref.watch(notificationPrefsProvider);
    final notifier = ref.read(notificationPrefsProvider.notifier);

    Widget row(String title, String? subtitle, bool value, String key, {bool enabled = true}) => ListRow(
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle).small.muted,
          trailing: Switch(value: value, onChanged: enabled ? (v) => notifier.set(key, v) : null),
        );

    return AppPage(
      title: 'Notifications',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          row('Enable notifications', null, prefs.enabled, SettingKeys.notificationsEnabled),
          const Gap(8),
          row('Meeting reminders', '24 hours before each meeting', prefs.meetings, SettingKeys.notifyMeetings,
              enabled: prefs.enabled),
          row('Contribution due', 'Morning of the meeting day', prefs.contributions, SettingKeys.notifyContributions,
              enabled: prefs.enabled),
          row('Loan repayments', '3 days before and when overdue', prefs.loans, SettingKeys.notifyLoans,
              enabled: prefs.enabled),
          row('Group activity', 'New transactions, members, loan decisions', prefs.activity, SettingKeys.notifyActivity,
              enabled: prefs.enabled),
        ],
      ),
    );
  }
}
