import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'notifier.dart';
import 'reminder_sink.dart';

/// System notifications over flutter_local_notifications. One channel
/// for sync events; ids from [notificationIdFor] replace repeats.
final class LocalNotifier implements Notifier {
  /// The plugin. Tests never construct this (platform channels).
  final FlutterLocalNotificationsPlugin _plugin;

  /// Whether [initialize] succeeded.
  bool _ready = false;

  /// Creates the notifier around [plugin].
  LocalNotifier([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Channel for group sync events.
  static const String channelId = LocalNotifierChannel.id;

  /// Initializes the plugin and asks for permission where required.
  /// Never throws: a phone that refuses still runs the app.
  Future<void> initialize() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(),
        macOS: DarwinInitializationSettings(),
        linux: LinuxInitializationSettings(
          defaultActionName: 'Open',
        ),
      );
      await _plugin.initialize(settings);
      final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >();
      await android?.requestNotificationsPermission();
      final ios = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin
      >();
      await ios?.requestPermissions(alert: true, badge: true, sound: true);
      final macos = _plugin.resolvePlatformSpecificImplementation<
        MacOSFlutterLocalNotificationsPlugin
      >();
      await macos?.requestPermissions(alert: true, badge: true, sound: true);
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    if (!_ready) {
      return;
    }
    try {
      await _plugin.show(
        id,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            LocalNotifierChannel.id,
            'Group sync',
            channelDescription: 'New transactions, members, loans.',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
          macOS: DarwinNotificationDetails(),
          linux: LinuxNotificationDetails(),
        ),
        payload: payload,
      );
    } catch (_) {}
  }
}
