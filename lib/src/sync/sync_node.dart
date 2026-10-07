import 'transport.dart';

/// One PubSub announcement from another vBank node.
final class SyncNotification {
  /// Group topic, `vbank/group/<id>`.
  final String topic;

  /// JSON body: version, kind, group id, CID and return addresses.
  final String content;

  /// Sending peer id.
  final String sender;

  /// Creates a notification.
  const SyncNotification(this.topic, this.content, this.sender);
}

/// The full node surface the sync coordinator needs: the engine boundary
/// ([SyncTransport]) plus lifecycle, topic subscriptions, announcements and
/// notifications.
///
/// `IpfsTransport` implements this over a real node; tests fake it.
abstract interface class SyncNode implements SyncTransport {
  /// True while running.
  bool get isRunning;

  /// Starts the node. Idempotent.
  Future<void> start();

  /// Subscribes to a group topic for announcements.
  Future<void> subscribe(String topic);

  /// Publishes an announcement to a group topic.
  Future<void> publish(String topic, String message, List<String> peers);

  /// PubSub announcements from other vBank nodes.
  Stream<SyncNotification> get notifications;
}
