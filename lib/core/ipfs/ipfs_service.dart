import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:dart_ipfs/dart_ipfs.dart' show PubSubMessage;
import 'package:flutter/foundation.dart' show debugPrint, kDebugMode, kProfileMode;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'ipfs_node_host.dart';
import 'ipfs_worker.dart';

enum IpfsNodeState { stopped, starting, running, stopping }

/// Raised on the main isolate for failures inside the IPFS worker.
class IpfsException implements Exception {
  final String message;
  const IpfsException(this.message);
  @override
  String toString() => 'IpfsException: $message';
}

/// Main-isolate facade over the IPFS node, which runs in a worker isolate.
///
/// Every libp2p handshake, DHT query, bitswap exchange and block fetch happens
/// off the UI isolate; this class only forwards commands and mirrors state.
/// The API is deliberately the same one the app used when the node was
/// in-process, so `SyncManager` and the screens did not change.
class IpfsService {
  /// vBank's own notification protocol (documented on [IpfsNodeHost.publish]).
  static const notifyProtocol = IpfsNodeHost.notifyProtocol;

  /// vBank's own block-fetch protocol (documented on [IpfsNodeHost.fetchFromPeers]).
  static const fetchProtocol = IpfsNodeHost.fetchProtocol;

  /// vBank's own request/response protocol (documented on [IpfsNodeHost.request]).
  static const syncProtocol = IpfsNodeHost.syncProtocol;

  /// Answers `/vbank/sync` requests from other nodes. Set by `SyncManager`;
  /// until then every request gets an empty reply.
  Future<Uint8List> Function(String from, Uint8List payload)? requestHandler;

  IpfsNodeState _state = IpfsNodeState.stopped;
  String? _peerId;
  List<String> _dialableAddresses = const [];

  final _stateController = StreamController<IpfsNodeState>.broadcast();
  final _notifyController = StreamController<PubSubMessage>.broadcast();

  Isolate? _isolate;
  ReceivePort? _fromWorker;
  SendPort? _toWorker;
  Future<void>? _spawning;
  int _nextId = 0;
  final _pending = <int, Completer<Object?>>{};
  bool _disposed = false;

  Stream<IpfsNodeState> get stateStream => _stateController.stream;
  IpfsNodeState get state => _state;
  String? get peerId => _peerId;
  bool get isRunning => _state == IpfsNodeState.running;

  /// Multiaddrs another vBank node can dial to reach this one (see
  /// [IpfsNodeHost.dialableAddresses]); empty until the node is running.
  List<String> get dialableAddresses => _dialableAddresses;

  /// Notifications from other vBank nodes (see [publish]). Safe to listen to
  /// before the node starts; the stream survives node restarts.
  Stream<PubSubMessage> get pubsubMessages => _notifyController.stream;

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

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

  Future<void> _ensureWorker() {
    if (_toWorker != null) return Future.value();
    return _spawning ??= () async {
      final dir = await _ensureIpfsDirectory();
      final port = ReceivePort();
      final ready = Completer<SendPort>();
      port.listen((message) => _onWorkerMessage(message, ready));
      _fromWorker = port;
      _isolate = await Isolate.spawn(
        ipfsWorkerMain,
        {'port': port.sendPort, 'ipfsDir': dir.path, 'debug': kDebugMode || kProfileMode},
        debugName: 'ipfs-worker',
        errorsAreFatal: false,
      );
      _toWorker = await ready.future;
      // If this isolate exits (Android finishes the activity on Back at the
      // root route), tell the worker to stop the node and exit too; otherwise
      // it would keep the port and the peer connections and deliver every
      // notification to a dead port.
      Isolate.current.addOnExitListener(_toWorker!, response: {'op': 'shutdown'});
      _spawning = null;
    }();
  }

  void _onWorkerMessage(Object? message, Completer<SendPort> ready) {
    final msg = message as Map<String, Object?>;
    switch (msg['event']) {
      case 'log':
        debugPrint(msg['line'] as String);
        return;
      case 'ready':
        ready.complete(msg['port'] as SendPort);
        return;
      case 'state':
        _peerId = msg['peerId'] as String?;
        _setState(IpfsNodeState.values.byName(msg['state'] as String));
        return;
      case 'addrs':
        _dialableAddresses = (msg['addrs'] as List).cast<String>();
        return;
      case 'request':
        _answerRequest(msg['reqId'] as int, msg['from'] as String, msg['payload'] as Uint8List);
        return;
      case 'notify':
        if (!_notifyController.isClosed) {
          _notifyController.add(PubSubMessage(
            topic: msg['topic'] as String,
            content: msg['content'] as String,
            sender: msg['sender'] as String,
          ));
        }
        return;
    }
    final id = msg['id'] as int?;
    final completer = id == null ? null : _pending.remove(id);
    if (completer == null) return;
    final error = msg['error'] as String?;
    if (error == null) {
      completer.complete(msg['result']);
    } else {
      switch (msg['kind']) {
        case 'state':
          completer.completeError(StateError(error));
        case 'timeout':
          completer.completeError(TimeoutException(error));
        default:
          completer.completeError(IpfsException(error));
      }
    }
  }

  Future<void> _answerRequest(int reqId, String from, Uint8List payload) async {
    Uint8List reply = Uint8List(0);
    try {
      final handler = requestHandler;
      if (handler != null) reply = await handler(from, payload);
    } catch (e) {
      // A failing handler must not leave the peer hanging.
      if (kDebugMode || kProfileMode) debugPrint('[ipfs] request handler failed: $e');
    }
    if (kDebugMode || kProfileMode) debugPrint('[ipfs] replying to request #$reqId with ${reply.length} bytes');
    if (_disposed || _toWorker == null) return;
    try {
      await _call<void>('respond', {'reqId': reqId, 'bytes': reply});
    } catch (_) {}
  }

  /// Sends [payload] to [peer] and returns its reply (see [IpfsNodeHost.request]).
  Future<Uint8List?> request(String peer, Uint8List payload, {Duration timeout = const Duration(seconds: 10)}) async {
    if (!isRunning) return null;
    return _call<Uint8List?>('request', {'peer': peer, 'payload': payload, 'timeoutMs': timeout.inMilliseconds});
  }

  Future<T> _call<T>(String op, [Map<String, Object?> args = const {}]) async {
    if (_disposed) throw StateError('IpfsService is disposed');
    await _ensureWorker();
    final id = _nextId++;
    final completer = Completer<Object?>();
    _pending[id] = completer;
    _toWorker!.send({'id': id, 'op': op, ...args});
    return (await completer.future) as T;
  }

  void _requireRunning() {
    if (!isRunning) throw StateError('IPFS node is not running');
  }

  Future<void> start() async {
    if (_state == IpfsNodeState.running || _state == IpfsNodeState.starting) return;
    _setState(IpfsNodeState.starting);
    try {
      await _call<void>('start');
    } catch (e) {
      _setState(IpfsNodeState.stopped);
      rethrow;
    }
  }

  Future<void> stop() async {
    if (_state != IpfsNodeState.running) return;
    await _call<void>('stop');
  }

  /// Stops the node, then tears down the worker and closes the streams.
  Future<void> dispose() async {
    try {
      await stop();
    } catch (_) {
      // Best effort on the way out.
    } finally {
      _disposed = true;
      for (final c in _pending.values) {
        if (!c.isCompleted) c.completeError(StateError('IpfsService disposed'));
      }
      _pending.clear();
      _isolate?.kill(priority: Isolate.immediate);
      _isolate = null;
      _fromWorker?.close();
      _toWorker = null;
      await _notifyController.close();
      await _stateController.close();
    }
  }

  void _setState(IpfsNodeState newState) {
    _state = newState;
    // Shutdown races: `stop()` reports progress while the provider is being
    // disposed, and the controller may already be closed by then.
    if (!_stateController.isClosed) _stateController.add(newState);
  }

  // ---------------------------------------------------------------------------
  // Content
  // ---------------------------------------------------------------------------

  Future<String> addData(Uint8List data) {
    _requireRunning();
    return _call<String>('addData', {'data': data});
  }

  Future<Uint8List?> getData(String cid) {
    _requireRunning();
    return _call<Uint8List?>('getData', {'cid': cid});
  }

  /// Reads a block from the local store only — never the network.
  Future<Uint8List?> getDataLocal(String cid) async {
    if (!isRunning) return null;
    return _call<Uint8List?>('getDataLocal', {'cid': cid});
  }

  /// Asks [peers] directly for [cid]; see [IpfsNodeHost.fetchFromPeers].
  Future<Uint8List?> fetchFromPeers(
    String cid,
    Iterable<String> peers, {
    Duration timeout = const Duration(seconds: 12),
  }) async {
    if (!isRunning) return null;
    return _call<Uint8List?>('fetchFromPeers', {
      'cid': cid,
      'peers': peers.toList(),
      'timeoutMs': timeout.inMilliseconds,
    });
  }

  Future<void> pin(String cid) {
    _requireRunning();
    return _call<void>('pin', {'cid': cid});
  }

  Future<void> unpin(String cid) {
    _requireRunning();
    return _call<void>('unpin', {'cid': cid});
  }

  // ---------------------------------------------------------------------------
  // Peers
  // ---------------------------------------------------------------------------

  Future<List<String>> get connectedPeers async {
    if (!isRunning) return const [];
    try {
      return (await _call<List>('connectedPeers')).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  Future<void> connectToPeer(String multiaddr) {
    _requireRunning();
    return _call<void>('connectToPeer', {'addr': multiaddr});
  }

  Future<List<String>> findProviders(String cid) async {
    _requireRunning();
    return (await _call<List>('findProviders', {'cid': cid})).cast<String>();
  }

  // ---------------------------------------------------------------------------
  // Notifications
  // ---------------------------------------------------------------------------

  Future<void> subscribe(String topic) {
    _requireRunning();
    return _call<void>('subscribe', {'topic': topic});
  }

  Future<void> unsubscribe(String topic) {
    _requireRunning();
    return _call<void>('unsubscribe', {'topic': topic});
  }

  /// Notifies known vBank peers of [message] on [topic]; returns how many
  /// accepted it. See [IpfsNodeHost.publish].
  Future<int> publish(String topic, String message, {Iterable<String> peers = const []}) {
    _requireRunning();
    return _call<int>('publish', {'topic': topic, 'message': message, 'peers': peers.toList()});
  }
}
