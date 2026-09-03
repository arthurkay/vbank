import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:dart_ipfs/dart_ipfs.dart';
// ignore: implementation_imports
import 'package:dart_ipfs/src/transport/libp2p_router.dart' show Libp2pRouter;
import 'package:path/path.dart' as p;

import 'raw_cid.dart';

/// The IPFS node itself. Lives inside the worker isolate (see `ipfs_worker.dart`)
/// so that libp2p handshakes, DHT chatter, bitswap and block fetches never run
/// on the UI isolate; `IpfsService` is the main-isolate proxy with the same
/// surface.
///
/// Everything here is plain Dart (`dart_ipfs`, `dart:io`) — no Flutter plugins,
/// which is what makes it safe to run in a background isolate.
class IpfsNodeHost {
  IpfsNodeHost({
    required this.ipfsDir,
    required this.onState,
    required this.onNotify,
    required this.onAddresses,
    required this.onRequest,
    this.listenPort = 4001,
    this.debugLog = false,
    this.identitySeed,
  });

  /// 32-byte libp2p identity seed. When null the node keeps one in
  /// `<ipfsDir>/identity_seed`. A relay on a host without persistent storage
  /// passes it in (from an environment secret) so its peer id never changes.
  final Uint8List? identitySeed;

  /// TCP port the node listens on (tests run two nodes in one process).
  final int listenPort;

  /// Print libp2p dial/stream failures (the package logger is silent at our
  /// log level). On in debug and profile builds.
  final bool debugLog;

  /// Writable, app-private directory for the datastore/keystore/log.
  final String ipfsDir;

  /// `(state, peerId)` whenever the node changes state.
  final void Function(String state, String? peerId) onState;

  /// A notification from another vBank node: `(topic, content, sender)`.
  final void Function(String topic, String content, String sender) onNotify;

  /// Our dialable multiaddrs, recomputed after start.
  final void Function(List<String> addrs) onAddresses;

  /// A `/vbank/sync` request from [from]; the returned bytes are the reply
  /// (empty for "nothing to say").
  final Future<Uint8List> Function(String from, Uint8List payload) onRequest;

  /// vBank's own request/response protocol (sync inventories), see [request].
  static const syncProtocol = '/vbank/sync/1.0.0';

  /// vBank's own notification protocol, see [publish].
  static const notifyProtocol = '/vbank/notify/1.0.0';

  /// vBank's own block-fetch protocol, see [fetchFromPeers].
  static const fetchProtocol = '/vbank/fetch/1.0.0';

  IPFSNode? _node;
  String? _peerId;
  bool _running = false;
  List<String> _localIPv4s = const [];
  StreamSubscription<PubSubMessage>? _nodePubSubSub;

  /// Peers known to run vBank: everyone we dialed from a peer book and everyone
  /// who has notified us. Public IPFS peers (bootstrap, DHT) never speak our
  /// protocol, and each attempt at them costs a 15 s stream-negotiation timeout.
  final _vbankPeers = <String>{};

  bool get isRunning => _running;
  String? get peerId => _peerId;

  void _dbg(String message) {
    // ignore: avoid_print
    if (debugLog) print('[ipfs_host] $message');
  }

  Future<void> start() async {
    if (_running) return;
    onState('starting', null);
    try {
      // dart_ipfs resolves several paths relative to the process working
      // directory ('./ipfs_data', './ipfs_keystore' and its own
      // 'ipfs_<pid>.log'). On Android the CWD is '/', which is read-only, so
      // every write fails. Point the CWD at a writable, app-private folder
      // and pass absolute paths for everything that is configurable.
      Directory.current = Directory(ipfsDir);
      Libp2pRouter.debugLog = debugLog;

      // No public DHT and no bootstrap peers: vBank nodes address each other
      // directly (invite links, snapshots and joins carry multiaddrs) and pull
      // inventories from known peers, so the public network adds nothing —
      // and dialing unreachable bootstrap nodes on every sync round was what
      // made rounds hit their 60 s budget.
      final config = IPFSConfig(
        libp2pIdentitySeed: await _identitySeed(),
        libp2pListenAddress: '/ip4/0.0.0.0/tcp/$listenPort',
        offline: false,
        debug: false,
        verboseLogging: false,
        logLevel: 'warning',
        datastorePath: p.join(ipfsDir, 'ipfs_data'),
        dataPath: p.join(ipfsDir, 'ipfs_data'),
        keystorePath: p.join(ipfsDir, 'ipfs_keystore'),
        enablePubSub: true,
        enableDHT: false,
        enableContentRouting: false,
        enableCircuitRelay: false,
        network: NetworkConfig(
          bootstrapPeers: const [],
          listenAddresses: ['/ip4/0.0.0.0/tcp/$listenPort'],
        ),
      );

      // A previous worker may still be releasing the port (see the shutdown
      // handling in ipfs_worker.dart), and dart_ipfs reports a node as started
      // even when its listener failed to bind — so check the port ourselves and
      // retry for a few seconds.
      IPFSNode? node;
      for (var attempt = 1; ; attempt++) {
        try {
          node = await IPFSNode.create(config);
          await node.start();
          if (await _isListening()) break;
          _dbg('node started but port $listenPort is not accepting connections (attempt $attempt)');
          try {
            await node.stop();
          } catch (_) {}
          node = null;
          if (attempt >= 5) throw StateError('Could not listen on TCP port $listenPort');
        } catch (e) {
          if (attempt >= 5) rethrow;
          _dbg('node start failed (attempt $attempt): $e — retrying');
        }
        await Future<void>.delayed(const Duration(seconds: 2));
      }
      _node = node;
      _peerId = node.peerID;
      _registerProtocols(node);
      await _refreshLocalAddresses();
      _running = true;
      onState('running', _peerId);
      onAddresses(dialableAddresses);
    } catch (e) {
      _node = null;
      _peerId = null;
      onState('stopped', null);
      rethrow;
    }
  }

  /// True when something accepts TCP connections on [listenPort] locally.
  Future<bool> _isListening() async {
    try {
      final socket = await Socket.connect(InternetAddress.loopbackIPv4, listenPort, timeout: const Duration(seconds: 2));
      socket.destroy();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// A random 32-byte seed created once and kept beside the datastore, so this
  /// node keeps the same peer id across restarts. Without it every start mints a
  /// new identity and every address other members hold for us goes stale.
  Future<Uint8List> _identitySeed() async {
    final injected = identitySeed;
    if (injected != null && injected.length == 32) return injected;
    final file = File(p.join(ipfsDir, 'identity_seed'));
    if (await file.exists()) {
      final bytes = await file.readAsBytes();
      if (bytes.length == 32) return bytes;
    }
    final rng = Random.secure();
    final seed = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    await file.writeAsBytes(seed, flush: true);
    if (!Platform.isWindows) await Process.run('chmod', ['600', file.path]);
    return seed;
  }

  Future<void> stop() async {
    final node = _node;
    if (!_running || node == null) return;
    onState('stopping', _peerId);
    try {
      await _nodePubSubSub?.cancel();
      _nodePubSubSub = null;
      await node.stop();
    } finally {
      _node = null;
      _peerId = null;
      _running = false;
      onState('stopped', null);
      onAddresses(const []);
    }
  }

  IPFSNode _require() {
    final node = _node;
    if (!_running || node == null) throw StateError('IPFS node is not running');
    return node;
  }

  Future<String> addData(Uint8List data) => _require().addFile(data);

  Future<Uint8List?> getData(String cid) => _require().get(cid);

  /// Reads a block from the local store only — never the network.
  Future<Uint8List?> getDataLocal(String cid) async {
    final node = _node;
    if (node == null) return null;
    try {
      final r = await node.blockStore.getBlock(cid);
      if (r.found && r.hasBlock()) return Uint8List.fromList(r.block.data);
    } catch (_) {
      // Treat store errors as a miss.
    }
    return null;
  }

  /// Multiaddrs another vBank node can dial to reach this one, each ending in
  /// `/p2p/<peerId>`. dart_ipfs listens on the wildcard address, so the
  /// wildcard is expanded to every non-loopback IPv4 interface — on a phone
  /// that is the Wi-Fi address, on a laptop usually one or two. TCP only:
  /// dart_ipfs cannot dial its own QUIC/WebTransport listeners.
  List<String> get dialableAddresses {
    final node = _node;
    final id = _peerId;
    if (node == null || id == null) return const [];
    final out = <String>{};
    for (final raw in node.addresses) {
      final addr = raw.split('/p2p/').first;
      final m = RegExp(r'^/ip4/([^/]+)/(tcp)/(\d+)(.*)$').firstMatch(addr);
      if (m == null) continue;
      final host = m.group(1)!;
      final rest = '/${m.group(2)}/${m.group(3)}${m.group(4)}';
      if (host == '0.0.0.0') {
        for (final ip in _localIPv4s) {
          out.add('/ip4/$ip$rest/p2p/$id');
        }
      } else if (host != '127.0.0.1') {
        out.add('/ip4/$host$rest/p2p/$id');
      }
    }
    return out.toList();
  }

  Future<void> _refreshLocalAddresses() async {
    try {
      final ifaces = await NetworkInterface.list(type: InternetAddressType.IPv4, includeLoopback: false);
      _localIPv4s = [
        for (final i in ifaces)
          for (final a in i.addresses)
            if (!a.address.startsWith('169.254.')) a.address,
      ];
    } catch (_) {
      _localIPv4s = const [];
    }
  }

  Future<List<String>> connectedPeers() async {
    final node = _node;
    if (node == null) return const [];
    try {
      return await node.connectedPeers;
    } catch (_) {
      return const [];
    }
  }

  Future<void> connectToPeer(String multiaddr) async {
    await _require().connectToPeer(await resolveMultiaddr(multiaddr));
    if (multiaddr.contains('/p2p/')) _vbankPeers.add(multiaddr.split('/p2p/').last);
  }

  static final _dnsAddr = RegExp(r'^/dns4?/([^/]+)/(tcp/\d+.*)$');

  /// `/dns4/relay.example.com/tcp/4001/p2p/Qm…` → `/ip4/203.0.113.7/tcp/4001/p2p/Qm…`.
  ///
  /// The libp2p stack dials IP addresses only; a relay is better named by a
  /// hostname (it survives an IP change and can sit behind a CNAME), so the
  /// lookup happens here, right before the dial. Non-DNS addresses pass through.
  static Future<String> resolveMultiaddr(String multiaddr) async {
    final m = _dnsAddr.firstMatch(multiaddr.trim());
    if (m == null) return multiaddr;
    final host = m.group(1)!;
    final rest = m.group(2)!;
    final v4 = await InternetAddress.lookup(host, type: InternetAddressType.IPv4);
    if (v4.isEmpty) throw SocketException('No IPv4 address for $host');
    return '/ip4/${v4.first.address}/$rest';
  }

  Future<List<String>> findProviders(String cid) => _require().findProviders(cid);
  Future<void> pin(String cid) => _require().pin(cid);
  Future<void> unpin(String cid) async => _require().unpin(cid);
  Future<void> subscribe(String topic) => _require().subscribe(topic);
  Future<void> unsubscribe(String topic) => _require().unsubscribe(topic);

  /// Publishes [message] on [topic] to every known vBank peer.
  ///
  /// dart_ipfs 1.11 ships a pubsub client whose mesh is never populated (it
  /// only grafts peers that graft it first, and nothing ever does) and whose
  /// incoming messages are never surfaced on `IPFSNode.pubsubMessages`. Two
  /// vBank nodes that are directly connected therefore never hear each other
  /// through it. Our notifications are tiny (a group id and a CID), so instead
  /// of gossip we push them over our own libp2p protocol — the same thing
  /// gossipsub's flood-publish does for small networks. The node's pubsub is
  /// still used as well, so if a future dart_ipfs fixes it nothing here breaks.
  ///
  /// [peers] are additional peer ids to notify even if the router does not
  /// list them as connected: its bookkeeping drops a peer on *any* connection
  /// close, including a rejected handshake on a second connection, while the
  /// live connection keeps working. Opening a stream is the real test.
  /// Returns how many peers accepted the notification.
  Future<int> publish(String topic, String message, List<String> peers) async {
    final node = _require();
    try {
      await node.publish(topic, message);
    } catch (_) {
      // Best effort; the direct notification below is what actually delivers.
    }
    final router = node.router;
    if (router == null) {
      _dbg('notify $topic: node has no router');
      return 0;
    }
    final bytes = Uint8List.fromList(utf8.encode(jsonEncode({'topic': topic, 'content': message})));
    final targets = {...peers, ...router.connectedPeers.where(_vbankPeers.contains)}..remove(_peerId);
    _vbankPeers.addAll(peers);
    _dbg('notify $topic → ${targets.length} target(s): $targets');
    var delivered = 0;
    await Future.wait(targets.map((peer) async {
      try {
        await router.sendMessage(peer, bytes, protocolId: notifyProtocol);
        delivered++;
      } catch (e) {
        // Not reachable right now; the next sync round redials.
        _dbg('notify to $peer failed: $e');
      }
    }));
    return delivered;
  }

  /// Asks [peers], one at a time, for [cid] over our own request/response
  /// protocol and returns the first block whose hash matches.
  ///
  /// Bitswap only asks peers the router currently lists as connected, and that
  /// list goes stale (see [publish]); a fresh stream to a known peer works
  /// whenever the peer is reachable at all. Records are small (a few KB), so a
  /// direct ask is also faster than the wantlist round trip.
  Future<Uint8List?> fetchFromPeers(String cid, List<String> peers, Duration timeout) async {
    final router = _node?.router;
    if (router == null) return null;
    final request = Uint8List.fromList(utf8.encode(jsonEncode({'cid': cid})));
    for (final peer in {...peers}..remove(_peerId)) {
      try {
        final response = await router.sendRequest(peer, fetchProtocol, request).timeout(timeout);
        if (response == null || response.isEmpty) continue;
        if (rawCidOf(response) != cid) continue; // not what we asked for
        _vbankPeers.add(peer);
        return response;
      } catch (e) {
        // Unreachable or slow; try the next peer.
        _dbg('fetch $cid from $peer failed: $e');
      }
    }
    return null;
  }

  /// Sends [payload] to [peer] over [syncProtocol] and returns its reply, or
  /// null when the peer is unreachable or silent.
  Future<Uint8List?> request(String peer, Uint8List payload, Duration timeout) async {
    final router = _node?.router;
    if (router == null) return null;
    try {
      final reply = await router.sendRequest(peer, syncProtocol, payload).timeout(timeout);
      if (reply != null) _vbankPeers.add(peer);
      return reply;
    } catch (e) {
      _dbg('request to $peer failed: $e');
      return null;
    }
  }

  void _registerProtocols(IPFSNode node) {
    node.router?.registerProtocolHandler(syncProtocol, (packet) async {
      try {
        _vbankPeers.add(packet.srcPeerId);
        final reply = await onRequest(packet.srcPeerId, packet.datagram);
        await packet.responder?.call(reply);
      } catch (_) {
        // Malformed request or the stream went away.
      }
    });
    node.router?.registerProtocolHandler(fetchProtocol, (packet) async {
      try {
        final m = jsonDecode(utf8.decode(packet.datagram)) as Map<String, dynamic>;
        final cid = m['cid'] as String?;
        _vbankPeers.add(packet.srcPeerId);
        final bytes = cid == null ? null : await getDataLocal(cid);
        await packet.responder?.call(bytes ?? Uint8List(0));
      } catch (_) {
        // Malformed request or the stream went away.
      }
    });
    node.router?.registerProtocolHandler(notifyProtocol, (packet) {
      try {
        final m = jsonDecode(utf8.decode(packet.datagram)) as Map<String, dynamic>;
        final topic = m['topic'] as String?;
        final content = m['content'] as String?;
        if (topic == null || content == null) return;
        _vbankPeers.add(packet.srcPeerId);
        onNotify(topic, content, packet.srcPeerId);
      } catch (_) {
        // Not ours / malformed: ignore.
      }
    });
    _nodePubSubSub?.cancel();
    _nodePubSubSub = node.pubsubMessages.listen(
      (m) => onNotify(m.topic, m.content, m.sender),
      onError: (_) {},
    );
  }
}
