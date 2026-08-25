import 'dart:async';

import 'package:dart_ipfs/dart_ipfs.dart';

class DiscoveryService {
  bool _isDiscovering = false;
  IPFSNode? _node;
  Timer? _dhtQueryTimer;
  final _peersController = StreamController<DiscoveredPeer>.broadcast();

  Stream<DiscoveredPeer> get peersStream => _peersController.stream;
  bool get isDiscovering => _isDiscovering;

  void attachNode(IPFSNode node) {
    _node = node;
  }

  Future<void> startDiscovery(String groupTopic) async {
    if (_isDiscovering) return;
    _isDiscovering = true;

    _startDhtDiscovery(groupTopic);
  }

  void _startDhtDiscovery(String groupTopic) {
    _dhtQueryTimer?.cancel();
    _dhtQueryTimer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (!_isDiscovering) {
        timer.cancel();
        return;
      }
      _queryDhtForGroupPeers(groupTopic);
    });
  }

  Future<void> _queryDhtForGroupPeers(String groupTopic) async {
    if (_node == null) return;

    try {
      final providers = await _node!.findProviders(groupTopic);
      for (final peerId in providers) {
        _peersController.add(DiscoveredPeer(
          peerId: peerId,
          address: '',
          method: DiscoveryMethod.dht,
          discoveredAt: DateTime.now().toUtc(),
        ));
      }
    } catch (e) {
      // DHT query failed silently
    }
  }

  Future<void> stopDiscovery() async {
    _isDiscovering = false;
    _dhtQueryTimer?.cancel();
    _dhtQueryTimer = null;
  }

  void dispose() {
    stopDiscovery();
    _peersController.close();
  }
}

class DiscoveredPeer {
  final String peerId;
  final String address;
  final DiscoveryMethod method;
  final DateTime discoveredAt;

  const DiscoveredPeer({
    required this.peerId,
    required this.address,
    required this.method,
    required this.discoveredAt,
  });
}

enum DiscoveryMethod { mdns, dht }
