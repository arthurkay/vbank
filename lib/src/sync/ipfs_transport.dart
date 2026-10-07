import 'dart:async';
import 'dart:typed_data';

import 'node_host.dart';
import 'sync_node.dart';
import 'transport.dart';

/// A [SyncTransport] over a real IPFS node ([IpfsNodeHost], itself over the
/// patched vendored `dart_ipfs`).
///
/// Besides the engine surface it exposes the node lifecycle, PubSub
/// notifications, dialable addresses and state changes for the sync
/// coordinator and screens.
final class IpfsTransport implements SyncNode {
  /// App-private directory for the datastore and identity seed.
  final String ipfsDir;

  /// TCP listen port.
  final int listenPort;

  /// Fixed identity for storage-less hosts, or null to keep one on disk.
  final Uint8List? identitySeed;

  /// Verbose libp2p logging (debug builds).
  final bool debugLog;

  /// Incoming sync-protocol handler (the engine installs its own).
  Future<Uint8List> Function(String from, Uint8List payload)? _onRequest;

  /// Creates the transport. Call [start] before use.
  IpfsTransport({
    required this.ipfsDir,
    this.listenPort = 4001,
    this.identitySeed,
    this.debugLog = false,
  });

  late final IpfsNodeHost _host = IpfsNodeHost(
    ipfsDir: ipfsDir,
    listenPort: listenPort,
    debugLog: debugLog,
    identitySeed: identitySeed,
    onState: (String state, String? peerId) =>
        _states.add((state, peerId)),
    onNotify: (String topic, String content, String sender) =>
        _notifications.add(SyncNotification(topic, content, sender)),
    onAddresses: (_) {},
    onRequest: (String from, Uint8List payload) async {
      final handler = _onRequest;
      if (handler == null) {
        return Uint8List(0);
      }
      return handler(from, payload);
    },
  );

  /// Node state changes: `(state, peerId)`.
  Stream<(String, String?)> get states => _states.stream;
  final StreamController<(String, String?)> _states =
      StreamController<(String, String?)>.broadcast();

  /// PubSub notifications from other vBank nodes.
  @override
  Stream<SyncNotification> get notifications => _notifications.stream;
  final StreamController<SyncNotification> _notifications =
      StreamController<SyncNotification>.broadcast();

  /// Starts the node. Idempotent.
  @override
  Future<void> start() => _host.start();

  /// Stops the node.
  Future<void> stop() => _host.stop();

  /// True while running.
  @override
  bool get isRunning => _host.isRunning;

  /// Our dialable multiaddrs for invites and snapshots.
  List<String> get dialableAddresses => _host.dialableAddresses;

  @override
  String? get peerId => _host.peerId;

  @override
  Future<Set<String>> get connectedPeers async =>
      (await _host.connectedPeers()).toSet();

  @override
  Future<void> connect(
    String addr, {
    Duration timeout = const Duration(seconds: 8),
  }) =>
      _host.connectToPeer(addr).timeout(timeout);

  @override
  Future<Uint8List?> request(String peerId, Uint8List payload) async {
    try {
      return await _host
          .request(peerId, payload, const Duration(seconds: 15))
          .timeout(const Duration(seconds: 20));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> fetchBlock(String cid, List<String> peerIds) async {
    try {
      final Uint8List? direct = await _host
          .fetchFromPeers(cid, peerIds, const Duration(seconds: 12))
          .timeout(const Duration(seconds: 15));
      if (direct != null) {
        return direct;
      }
      return await _host.getData(cid).timeout(const Duration(seconds: 30));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String> addData(Uint8List bytes) => _host.addData(bytes);

  @override
  Future<Uint8List?> localBlock(String cid) => _host.getDataLocal(cid);

  @override
  set onRequest(
    Future<Uint8List> Function(String from, Uint8List payload)? handler,
  ) {
    _onRequest = handler;
  }

  /// Subscribes to a group topic for announcements.
  @override
  Future<void> subscribe(String topic) => _host.subscribe(topic);

  /// Publishes an announcement; returns peers reached.
  @override
  Future<int> publish(
    String topic,
    String message,
    List<String> peers,
  ) =>
      _host.publish(topic, message, peers);

  /// Pins a block against garbage collection.
  Future<void> pin(String cid) => _host.pin(cid);

  /// Resolves `/dns4/…` and `/ip4/…` multiaddrs to dialable form.
  static Future<String> resolveMultiaddr(String multiaddr) =>
      IpfsNodeHost.resolveMultiaddr(multiaddr);
}
