import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// A dated reminder. The app schedules them; tests record them.
abstract interface class ReminderSink {
  /// Schedules (replacing any with [id]) a reminder for [at] (UTC).
  /// No-op when [at] is past.
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  });

  /// Cancels [id], e.g. after a meeting moves. No-op when absent.
  Future<void> cancel(int id);
}

/// Records reminders in memory, for tests.
final class MemoryReminderSink implements ReminderSink {
  /// Scheduled reminders `(id, title, body, at)`.
  final List<(int, String, String, DateTime)> scheduled = [];

  /// Cancelled ids.
  final List<int> cancelled = [];

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    scheduled.add((id, title, body, at));
  }

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
  }
}

/// Exact-alarm reminders over flutter_local_notifications. Times are
/// stored UTC and converted to the device zone at schedule time.
final class PluginReminderSink implements ReminderSink {
  /// The plugin (initialized by [LocalNotifier]).
  final FlutterLocalNotificationsPlugin plugin;

  /// Creates the sink.
  const PluginReminderSink(this.plugin);

  @override
  Future<void> schedule({
    required int id,
    required String title,
    required String body,
    required DateTime at,
  }) async {
    if (!at.toUtc().isAfter(DateTime.now().toUtc())) {
      return;
    }
    try {
      await plugin.zonedSchedule(
        id,
        title,
        body,
        tz.TZDateTime.from(at.toUtc(), tz.local),
        const NotificationDetails(
          android: AndroidNotificationDetails(
            LocalNotifierChannel.id,
            'Reminders',
            channelDescription: 'Meetings and repayments due.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {}
  }

  @override
  Future<void> cancel(int id) async {
    try {
      await plugin.cancel(id);
    } catch (_) {}
  }
}

/// Channel constants shared with [LocalNotifier].
abstract final class LocalNotifierChannel {
  /// Sync-event channel id.
  static const String id = 'vbank_sync';
}
