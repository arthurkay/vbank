import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'ipfs_node_host.dart';

/// Entry point of the IPFS worker isolate.
///
/// Protocol (all messages are plain maps so they cross the isolate boundary):
///
///   main → worker   {'id': int, 'op': String, ...args}
///   worker → main   {'id': int, 'result': Object?}          reply
///                   {'id': int, 'error': String, 'kind': String}
///                   {'event': 'state', 'state': String, 'peerId': String?}
///                   {'event': 'notify', 'topic', 'content', 'sender'}
///                   {'event': 'addrs', 'addrs': `List<String>`}
///                   {'event': 'request', 'reqId': int, 'from': String, 'payload': Uint8List}
///                   {'event': 'ready', 'port': SendPort}    once, at start
///   main → worker   {'id': int, 'op': 'respond', 'reqId': int, 'bytes': Uint8List}
void ipfsWorkerMain(Map<String, Object?> init) {
  final toMain = init['port'] as SendPort;
  // Route this isolate's prints through the main isolate: `flutter test`
  // (and some log collectors) only capture the root isolate's output.
  runZoned(
    () => _workerBody(init, toMain),
    zoneSpecification: ZoneSpecification(
      print: (self, parent, zone, line) => toMain.send({'event': 'log', 'line': line}),
    ),
  );
}

void _workerBody(Map<String, Object?> init, SendPort toMain) {
  final ipfsDir = init['ipfsDir'] as String;
  final inbox = ReceivePort();

  // Inbound sync requests are answered by the main isolate (it owns the
  // database); park them here until the reply comes back.
  var nextReqId = 0;
  final pendingRequests = <int, Completer<Uint8List>>{};

  final host = IpfsNodeHost(
    ipfsDir: ipfsDir,
    debugLog: init['debug'] == true,
    onState: (state, peerId) => toMain.send({'event': 'state', 'state': state, 'peerId': peerId}),
    onNotify: (topic, content, sender) {
      toMain.send({'event': 'notify', 'topic': topic, 'content': content, 'sender': sender});
      if (init['debug'] == true) print('[ipfs_worker] notify from $sender → main (sent)'); // ignore: avoid_print
    },
    onAddresses: (addrs) => toMain.send({'event': 'addrs', 'addrs': addrs}),
    onRequest: (from, payload) {
      final reqId = nextReqId++;
      final completer = Completer<Uint8List>();
      pendingRequests[reqId] = completer;
      if (init['debug'] == true) print('[ipfs_worker] request #$reqId from $from → main'); // ignore: avoid_print
      toMain.send({'event': 'request', 'reqId': reqId, 'from': from, 'payload': payload});
      return completer.future.timeout(const Duration(seconds: 10), onTimeout: () {
        pendingRequests.remove(reqId);
        return Uint8List(0);
      });
    },
  );

  inbox.listen((message) async {
    final msg = message as Map<String, Object?>;
    if (msg['op'] == 'shutdown') {
      // The main isolate is gone (on Android, Back at the root route finishes
      // the activity and the root isolate with it). Release the port and the
      // peer connections so the next root isolate can start a fresh node.
      try {
        await host.stop();
      } catch (_) {}
      inbox.close();
      Isolate.exit();
    }
    final id = msg['id'] as int;
    if (msg['op'] == 'respond') {
      final completer = pendingRequests.remove(msg['reqId'] as int);
      if (init['debug'] == true) print('[ipfs_worker] respond #${msg['reqId']} (${completer == null ? 'late' : 'ok'})'); // ignore: avoid_print
      completer?.complete(msg['bytes'] as Uint8List);
      toMain.send({'id': id, 'result': null});
      return;
    }
    try {
      final result = await _dispatch(host, msg);
      toMain.send({'id': id, 'result': result});
    } on StateError catch (e) {
      toMain.send({'id': id, 'error': e.message, 'kind': 'state'});
    } on TimeoutException catch (e) {
      toMain.send({'id': id, 'error': e.message ?? 'timeout', 'kind': 'timeout'});
    } catch (e) {
      toMain.send({'id': id, 'error': e.toString(), 'kind': 'other'});
    }
  });

  toMain.send({'event': 'ready', 'port': inbox.sendPort});
}

Future<Object?> _dispatch(IpfsNodeHost host, Map<String, Object?> m) async {
  switch (m['op'] as String) {
    case 'start':
      await host.start();
      return null;
    case 'stop':
      await host.stop();
      return null;
    case 'addData':
      return host.addData(m['data'] as dynamic);
    case 'getData':
      return host.getData(m['cid'] as String);
    case 'getDataLocal':
      return host.getDataLocal(m['cid'] as String);
    case 'fetchFromPeers':
      return host.fetchFromPeers(
        m['cid'] as String,
        (m['peers'] as List).cast<String>(),
        Duration(milliseconds: m['timeoutMs'] as int),
      );
    case 'connectedPeers':
      return host.connectedPeers();
    case 'connectToPeer':
      await host.connectToPeer(m['addr'] as String);
      return null;
    case 'findProviders':
      return host.findProviders(m['cid'] as String);
    case 'pin':
      await host.pin(m['cid'] as String);
      return null;
    case 'unpin':
      await host.unpin(m['cid'] as String);
      return null;
    case 'subscribe':
      await host.subscribe(m['topic'] as String);
      return null;
    case 'unsubscribe':
      await host.unsubscribe(m['topic'] as String);
      return null;
    case 'request':
      return host.request(
        m['peer'] as String,
        m['payload'] as Uint8List,
        Duration(milliseconds: m['timeoutMs'] as int),
      );
    case 'publish':
      return host.publish(m['topic'] as String, m['message'] as String, (m['peers'] as List).cast<String>());
    default:
      throw ArgumentError('Unknown op ${m['op']}');
  }
}
