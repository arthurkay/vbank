import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/core/result.dart';
import 'package:vbank/src/domain/repositories.dart';
import 'package:vbank/src/sync/transport.dart';

/// Map-backed [SettingsRepository] for sync-layer tests. No database, no
/// platform channels.
final class MemorySettingsRepository implements SettingsRepository {
  /// Stored values by key.
  final Map<String, Uint8List> store = {};

  /// Keys whose reads fail, for error-path tests.
  final Set<String> failOn = {};

  @override
  Future<Result<Uint8List?>> get(String key) async {
    if (failOn.contains(key)) {
      return const Err(StorageFailure('unavailable'));
    }
    return Ok(store[key]);
  }

  @override
  Future<Result<Unit>> set(String key, Uint8List value) async {
    store[key] = value;
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> remove(String key) async {
    store.remove(key);
    return const Ok(unit);
  }

  @override
  Future<void> close() async {}
}

/// An in-memory [SyncTransport] peer: routable requests, served blocks and
/// a served inventory, with programmable outages and full call journals.
///
/// By default it answers `inventory` from [inventoryCids] and accepts
/// `put` into [blocks] like a miniature relay. Tests proving the engine's
/// serve side replace [handler] with `engine.handleRequest`.
final class FakeTransport implements SyncTransport {
  /// This peer's id.
  @override
  String? peerId;

  /// Blocks served by [fetchBlock] and stored by `put`, by CID.
  final Map<String, Uint8List> blocks = {};

  /// CIDs served in `inventory` replies, newest first.
  final List<String> inventoryCids = [];

  /// Routable peers by id. Requests to unknown ids return null.
  final Map<String, FakeTransport> network = {};

  /// Peers whose connections fail: dials throw, requests return null.
  final Set<String> downPeers = {};

  /// Request counts per peer id.
  final Map<String, int> requests = {};

  /// Every address passed to [connect], in order.
  final List<String> dials = [];

  /// CIDs received via `put`, per sender... keyed by relay peer id (self).
  final List<String> putsReceived = [];

  /// Creates a peer with [peerId].
  FakeTransport(this.peerId);

  @override
  Future<Set<String>> get connectedPeers async =>
      network.keys.where((String id) => !downPeers.contains(id)).toSet();

  @override
  Future<void> connect(
    String addr, {
    Duration timeout = const Duration(seconds: 8),
  }) async {
    dials.add(addr);
    final String id = addr.split('/p2p/').last;
    if (downPeers.contains(id) || !network.containsKey(id)) {
      throw StateError('unreachable $id');
    }
  }

  @override
  Future<Uint8List?> request(String peer, Uint8List payload) async {
    requests[peer] = (requests[peer] ?? 0) + 1;
    if (downPeers.contains(peer)) {
      return null;
    }
    final FakeTransport? remote = network[peer];
    if (remote == null) {
      return null;
    }
    return remote.handle(peerId ?? '', payload);
  }

  @override
  Future<Uint8List?> fetchBlock(String cid, List<String> peerIds) async {
    if (blocks.containsKey(cid)) {
      return blocks[cid];
    }
    for (final String id in peerIds) {
      if (downPeers.contains(id)) {
        continue;
      }
      final Uint8List? bytes = network[id]?.blocks[cid];
      if (bytes != null) {
        return bytes;
      }
    }
    return null;
  }

  /// Installed request handler (an engine proving its serve side, or null
  /// for the miniature default below).
  Future<Uint8List> Function(String from, Uint8List payload)? _onRequest;

  @override
  set onRequest(
    Future<Uint8List> Function(String from, Uint8List payload)? handler,
  ) {
    _onRequest = handler;
  }

  /// Dispatches an incoming request through the installed handler.
  Future<Uint8List> handle(String from, Uint8List payload) =>
      _onRequest == null
          ? _defaultHandle(from, payload)
          : _onRequest!(from, payload);

  /// Miniature relay/member: serves [inventoryCids], stores `put` blocks.
  Future<Uint8List> _defaultHandle(String from, Uint8List payload) async {
    Map<String, dynamic> req;
    try {
      req = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (_) {
      return Uint8List(0);
    }
    if (req['op'] == 'inventory') {
      return Uint8List.fromList(
        utf8.encode(jsonEncode({'v': 1, 'cids': inventoryCids})),
      );
    }
    if (req['op'] == 'put') {
      final String? cid = req['cid'] as String?;
      final String? block = req['block'] as String?;
      if (cid == null || block == null) {
        return Uint8List(0);
      }
      blocks[cid] = base64Decode(block);
      if (!inventoryCids.contains(cid)) {
        inventoryCids.insert(0, cid);
      }
      putsReceived.add(cid);
      return Uint8List.fromList(
        utf8.encode(jsonEncode({'v': 1, 'stored': true, 'new': true})),
      );
    }
    return Uint8List(0);
  }
}
