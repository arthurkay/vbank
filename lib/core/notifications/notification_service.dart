import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class NotificationService {
  static final NotificationService _instance = NotificationService._();
  factory NotificationService() => _instance;
  NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool get isInitialized => _initialized;

  Future<void> initialize() async {
    if (_initialized) return;

    tz.initializeTimeZones();

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    await _plugin.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
    );
    // Android 13+ runtime permission.
    await _plugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _initialized = true;
  }

  /// Stable notification id from a string key (FNV-1a, 31-bit) so the same
  /// logical notification can be cancelled or replaced later.
  static int idFor(String key) {
    var hash = 0x811C9DC5;
    for (final c in key.codeUnits) {
      hash ^= c;
      hash = (hash * 0x01000193) & 0xFFFFFFFF;
    }
    return hash & 0x7FFFFFFF;
  }

  static const _immediate = NotificationDetails(
    android: AndroidNotificationDetails(
      'vbank_channel',
      'vBank Notifications',
      channelDescription: 'Notifications for vBank transactions and meetings',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
  );

  static const _scheduled = NotificationDetails(
    android: AndroidNotificationDetails(
      'vbank_scheduled',
      'vBank Scheduled',
      channelDescription: 'Scheduled notifications for vBank meetings and repayments',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(presentAlert: true, presentBadge: true, presentSound: true),
  );

  Future<void> showNotification({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_initialized) return;
    await _plugin.show(id, title, body, _immediate, payload: payload);
  }

  /// Schedules at an absolute instant. We express it in UTC, so the device's
  /// local zone (which `tz.local` may not know) is irrelevant.
  Future<void> scheduleNotification({
    required int id,
    required String title,
    required String body,
    required DateTime scheduledDate,
    String? payload,
  }) async {
    if (!_initialized) return;
    if (!scheduledDate.isAfter(DateTime.now())) return;

    final when = tz.TZDateTime.from(scheduledDate.toUtc(), tz.UTC);
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      when,
      _scheduled,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      payload: payload,
    );
  }

  Future<void> cancelNotification(int id) => _plugin.cancel(id);
  Future<void> cancelAllNotifications() => _plugin.cancelAll();
}
