import 'dart:async';

import 'package:dart_ipfs/dart_ipfs.dart' as ipfs;

class PubSubService {
  final _messageController = StreamController<VBankPubSubMessage>.broadcast();
  StreamSubscription? _subscription;
  final _subscribedTopics = <String>{};
  ipfs.IPFSNode? _node;

  Stream<VBankPubSubMessage> get messageStream => _messageController.stream;

  void attachNode(ipfs.IPFSNode node) {
    _node = node;
  }

  Future<void> subscribe(String topic) async {
    if (_node == null) throw StateError('No IPFS node attached');
    if (_subscribedTopics.contains(topic)) return;

    await _node!.subscribe(topic);
    _subscribedTopics.add(topic);

    _subscription?.cancel();
    _subscription = _node!.pubsubMessages.listen((msg) {
      if (_subscribedTopics.contains(msg.topic)) {
        _messageController.add(VBankPubSubMessage(
          topic: msg.topic,
          data: msg.content,
          fromPeerId: msg.sender,
          receivedAt: DateTime.now().toUtc(),
        ));
      }
    });
  }

  Future<void> unsubscribe(String topic) async {
    if (_node == null) return;
    if (!_subscribedTopics.contains(topic)) return;

    await _node!.unsubscribe(topic);
    _subscribedTopics.remove(topic);

    if (_subscribedTopics.isEmpty) {
      await _subscription?.cancel();
      _subscription = null;
    }
  }

  Future<void> publish(String topic, String message) async {
    if (_node == null) throw StateError('No IPFS node attached');
    await _node!.publish(topic, message);
  }

  Future<void> unsubscribeAll() async {
    if (_node == null) return;
    for (final topic in _subscribedTopics.toList()) {
      await _node!.unsubscribe(topic);
    }
    _subscribedTopics.clear();
    await _subscription?.cancel();
    _subscription = null;
  }

  void dispose() {
    _subscription?.cancel();
    _messageController.close();
  }
}

class VBankPubSubMessage {
  final String topic;
  final String data;
  final String fromPeerId;
  final DateTime receivedAt;

  const VBankPubSubMessage({
    required this.topic,
    required this.data,
    required this.fromPeerId,
    required this.receivedAt,
  });
}
