/// Shows notifications. The app wires [LocalNotifier]; tests record
/// into [MemoryNotifier]. Screens and services never touch plugins.
abstract interface class Notifier {
  /// Shows a notification now, replacing any with the same [id].
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  });
}

/// Records notifications in memory, for tests.
final class MemoryNotifier implements Notifier {
  /// Shown notifications `(id, title, body)` in order.
  final List<(int, String, String)> shown = [];

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    String? payload,
  }) async {
    shown.add((id, title, body));
  }
}
