import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:dart_ipfs/dart_ipfs.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

enum IpfsNodeState { stopped, starting, running, stopping }

class IpfsService {
  IPFSNode? _node;
  IpfsNodeState _state = IpfsNodeState.stopped;
  String? _peerId;

  final _stateController = StreamController<IpfsNodeState>.broadcast();
  Stream<IpfsNodeState> get stateStream => _stateController.stream;

  IpfsNodeState get state => _state;
  String? get peerId => _peerId;
  bool get isRunning => _state == IpfsNodeState.running;
  IPFSNode? get node => _node;

  Future<void> start() async {
    if (_state == IpfsNodeState.running || _state == IpfsNodeState.starting) return;

    _setState(IpfsNodeState.starting);

    try {
      // dart_ipfs resolves several paths relative to the process working
      // directory ('./ipfs_data', './ipfs_keystore' and its own
      // 'ipfs_<pid>.log'). On Android the CWD is '/', which is read-only, so
      // every write fails. Point the CWD at a writable, app-private folder
      // and pass absolute paths for everything that is configurable.
      final ipfsDir = await _ensureIpfsDirectory();
      Directory.current = ipfsDir;

      final config = IPFSConfig(
        offline: false,
        debug: false,
        verboseLogging: false,
        logLevel: 'warning',
        datastorePath: p.join(ipfsDir.path, 'ipfs_data'),
        dataPath: p.join(ipfsDir.path, 'ipfs_data'),
        keystorePath: p.join(ipfsDir.path, 'ipfs_keystore'),
        enablePubSub: true,
        enableDHT: true,
        enableContentRouting: true,
        enableCircuitRelay: true,
        network: NetworkConfig(
          bootstrapPeers: [
            '/dnsaddr/bootstrap.libp2p.io/p2p/QmNnooDu7bfjPFoTZYxP924oLpi7Kk2jN6Zy6G5KZC4YH3',
            '/dnsaddr/bootstrap.libp2p.io/p2p/QmQCU2EcMqAqQTH2XGCz4SMuEHaQKp8qBZPEJkUfh1M8yS',
            '/dnsaddr/bootstrap.libp2p.io/p2p/QmcZf59bWwK5XFi76jZXrFBHnYYW8yAHjmWSBA4vGc5GC',
          ],
        ),
      );

      _node = await IPFSNode.create(config);
      await _node!.start();

      _peerId = _node!.peerID;
      _setState(IpfsNodeState.running);
    } catch (e) {
      _node = null;
      _setState(IpfsNodeState.stopped);
      rethrow;
    }
  }

  static Future<Directory> _ensureIpfsDirectory() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory(p.join(support.path, 'ipfs'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// Call once at app startup (after `WidgetsFlutterBinding.ensureInitialized`).
  ///
  /// dart_ipfs's logger starts writing `ipfs_<pid>.log` relative to the CWD as
  /// soon as any of its classes are constructed — well before [start] runs —
  /// so the working directory must already be writable by then.
  static Future<void> prepareWorkingDirectory() async {
    Directory.current = await _ensureIpfsDirectory();
  }

  Future<void> stop() async {
    if (_state != IpfsNodeState.running || _node == null) return;

    _setState(IpfsNodeState.stopping);

    try {
      await _node!.stop();
    } finally {
      _node = null;
      _peerId = null;
      _setState(IpfsNodeState.stopped);
    }
  }

  Future<String> addData(Uint8List data) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    return await _node!.addFile(data);
  }

  Future<Uint8List?> getData(String cid) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    return await _node!.get(cid);
  }

  /// Dials a peer by multiaddr (best effort; used after DHT provider lookups).
  Future<void> connectToPeer(String multiaddr) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    await _node!.connectToPeer(multiaddr);
  }

  Future<List<String>> findProviders(String cid) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    return await _node!.findProviders(cid);
  }

  Future<void> pin(String cid) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    await _node!.pin(cid);
  }

  Future<void> unpin(String cid) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    await _node!.unpin(cid);
  }

  Future<void> subscribe(String topic) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    await _node!.subscribe(topic);
  }

  Future<void> unsubscribe(String topic) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    await _node!.unsubscribe(topic);
  }

  Future<void> publish(String topic, String message) async {
    if (!isRunning || _node == null) throw StateError('IPFS node is not running');
    await _node!.publish(topic, message);
  }

  Stream<PubSubMessage> get pubsubMessages {
    if (_node == null) return const Stream.empty();
    return _node!.pubsubMessages;
  }

  void _setState(IpfsNodeState newState) {
    _state = newState;
    // Shutdown races: `stop()` reports progress while the provider is being
    // disposed, and the controller may already be closed by then.
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  /// Stops the node, then closes the state stream. Awaiting the stop first
  /// keeps the final transitions observable; closing first would make them
  /// throw.
  Future<void> dispose() async {
    try {
      await stop();
    } finally {
      await _stateController.close();
    }
  }
}
