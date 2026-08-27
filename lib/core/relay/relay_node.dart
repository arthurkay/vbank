import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../ipfs/ipfs_node_host.dart';
import '../ipfs/raw_cid.dart';

/// An always-on vBank peer that lets members reach each other across the
/// internet.
///
/// Phones sit behind carrier NAT and cannot accept connections, so two phones
/// on different networks never see each other directly. A relay is a node with
/// a public address that every device dials *out* to. It speaks the same three
/// protocols as a member:
///
/// * `/vbank/sync` — answers `inventory` (the CIDs it holds for a group) and a
///   relay-only `put` (a device hands over one encrypted block; the relay
///   verifies the CID, stores it and forwards the notification to the other
///   devices interested in that group).
/// * `/vbank/fetch` — serves stored blocks (handled by [IpfsNodeHost]).
/// * `/vbank/notify` — a device announcing a record; the relay tries to fetch
///   it directly (works for desktops), otherwise waits for the `put`.
///
/// The relay holds **no group key**: every block is encrypted with the group
/// passphrase-derived key before it leaves a device (see `SyncEnvelope`), and
/// group ids and CIDs are opaque. It learns only "these peers talk about this
/// group id", which is what it needs to forward notifications.
class RelayNode {
  RelayNode({
    required this.dataDir,
    this.listenPort = 4001,
    this.publicIp,
    this.debugLog = false,
    void Function(String line)? log,
  }) : _log = log ?? ((l) => stdout.writeln('[relay] $l'));

  final String dataDir;
  final int listenPort;
  final String? publicIp;
  final bool debugLog;
  final void Function(String line) _log;

  late final IpfsNodeHost _host = IpfsNodeHost(
    ipfsDir: dataDir,
    listenPort: listenPort,
    debugLog: debugLog,
    onState: (state, peerId) => _log('node $state${peerId == null ? '' : ' as $peerId'}'),
    onNotify: _onNotify,
    onAddresses: (_) {},
    onRequest: _onRequest,
  );

  /// groupId → CIDs, newest first. Persisted as JSON.
  final Map<String, List<String>> _ledger = {};

  /// groupId → peers that asked about or pushed for it (in-memory).
  final Map<String, Set<String>> _interest = {};

  static const _maxPerGroup = 5000;
  int blocksStored = 0;
  int notificationsForwarded = 0;

  String get _ledgerPath => p.join(dataDir, 'relay_ledger.json');
  String? get peerId => _host.peerId;
  bool get isRunning => _host.isRunning;

  /// The address members put in the app (Settings → Relay) or that rides in
  /// invite links.
  String? get publicMultiaddr {
    final id = _host.peerId;
    if (id == null) return null;
    final ip = publicIp;
    if (ip != null && ip.isNotEmpty) return '/ip4/$ip/tcp/$listenPort/p2p/$id';
    return _host.dialableAddresses.firstOrNull;
  }

  Future<void> start() async {
    await Directory(dataDir).create(recursive: true);
    await _loadLedger();
    await _host.start();
    _log('listening on tcp/$listenPort, ${_ledger.length} group(s), ${_ledger.values.fold<int>(0, (n, l) => n + l.length)} block(s)');
    final addr = publicMultiaddr;
    if (addr != null) _log('relay address: $addr');
  }

  Future<void> stop() async {
    await _saveLedger();
    await _host.stop();
  }

  // ------------------------------------------------------------- protocols --

  Future<Uint8List> _onRequest(String from, Uint8List payload) async {
    Map<String, dynamic> req;
    try {
      req = jsonDecode(utf8.decode(payload)) as Map<String, dynamic>;
    } catch (_) {
      return Uint8List(0);
    }
    final groupId = req['groupId'] as String?;
    if (groupId == null || groupId.isEmpty) return Uint8List(0);
    _interested(groupId, from);
    switch (req['op']) {
      case 'inventory':
        final cids = _ledger[groupId] ?? const [];
        return Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'cids': cids, 'relay': true})));
      case 'put':
        final cid = req['cid'] as String?;
        final blockB64 = req['block'] as String?;
        if (cid == null || blockB64 == null) return Uint8List(0);
        Uint8List block;
        try {
          block = base64Decode(blockB64);
        } catch (_) {
          return Uint8List(0);
        }
        if (rawCidOf(block) != cid) {
          _log('rejected block from $from: CID mismatch');
          return Uint8List(0);
        }
        final fresh = await _store(groupId, cid, block);
        if (fresh) {
          await _forward(groupId, cid, from, (req['addrs'] as List?)?.cast<String>() ?? const []);
        }
        return Uint8List.fromList(utf8.encode(jsonEncode({'v': 1, 'stored': true, 'new': fresh})));
      default:
        return Uint8List(0);
    }
  }

  void _onNotify(String topic, String content, String sender) {
    Map<String, dynamic> note;
    try {
      note = jsonDecode(content) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final groupId = note['groupId'] as String?;
    final cid = note['cid'] as String?;
    if (groupId == null || cid == null) return;
    _interested(groupId, sender);
    if ((_ledger[groupId] ?? const []).contains(cid)) return;
    // Desktops and LAN peers can be fetched from; phones will follow up with
    // a `put`.
    unawaited(_host.fetchFromPeers(cid, [sender], const Duration(seconds: 12)).then((bytes) async {
      if (bytes == null) return;
      if (await _store(groupId, cid, bytes)) {
        await _forward(groupId, cid, sender, (note['addrs'] as List?)?.cast<String>() ?? const []);
      }
    }).catchError((_) {}));
  }

  void _interested(String groupId, String peer) {
    (_interest[groupId] ??= <String>{}).add(peer);
  }

  Future<bool> _store(String groupId, String cid, Uint8List block) async {
    final list = _ledger[groupId] ??= <String>[];
    if (list.contains(cid)) return false;
    final stored = await _host.addData(block);
    if (stored != cid) {
      // Different CID codec/hash than ours — keep what the device calls it so
      // fetches by that name still resolve to the same bytes.
      _log('note: stored $stored for advertised $cid');
    }
    await _host.pin(stored);
    list.insert(0, cid);
    if (list.length > _maxPerGroup) list.removeRange(_maxPerGroup, list.length);
    blocksStored++;
    await _saveLedger();
    return true;
  }

  /// Tells every other device interested in the group. They fetch the block
  /// from us over the connection they already hold.
  Future<void> _forward(String groupId, String cid, String from, List<String> addrs) async {
    final targets = {...?_interest[groupId]}..remove(from)..remove(_host.peerId);
    if (targets.isEmpty) return;
    final content = jsonEncode({'v': 1, 'kind': 'relay', 'groupId': groupId, 'cid': cid, 'addrs': addrs});
    // The host also nudges every connected vBank peer; harmless (opaque ids and
    // CIDs) and it covers a device whose interest we have not recorded yet.
    final n = await _host.publish('vbank/group/$groupId', content, targets.toList());
    notificationsForwarded += n;
    _log('forwarded $cid for $groupId to $n peer(s)');
  }

  // --------------------------------------------------------------- ledger --

  Future<void> _loadLedger() async {
    final f = File(_ledgerPath);
    if (!await f.exists()) return;
    try {
      final m = jsonDecode(await f.readAsString()) as Map<String, dynamic>;
      for (final e in m.entries) {
        _ledger[e.key] = (e.value as List).cast<String>();
      }
    } catch (e) {
      _log('ledger unreadable, starting empty: $e');
    }
  }

  Future<void> _saveLedger() async {
    final tmp = File('$_ledgerPath.tmp');
    await tmp.writeAsString(jsonEncode(_ledger), flush: true);
    await tmp.rename(_ledgerPath);
  }
}
