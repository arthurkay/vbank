import 'dart:typed_data';

/// The narrow boundary between the sync engine and the P2P stack.
///
/// The vendored `dart_ipfs` node (plus its vBank patches), libp2p dialing,
/// Bitswap fetching and PubSub all hide behind this. The engine speaks only
/// peers, CIDs and bytes; a fake implements the same surface in tests.
///
/// Payload shapes stay wire-identical to the legacy app (`{'op': ...}`
/// JSON), so rewritten nodes interoperate with old ones and the relay.
abstract interface class SyncTransport {
  /// Our own peer id, or null before the node starts.
  String? get peerId;

  /// Peers with a live connection right now.
  Future<Set<String>> get connectedPeers;

  /// Dials a full multiaddr (`/dns4/…/tcp/…/p2p/…`). Best effort: throws on
  /// failure or [timeout]; the engine treats dial errors as hints, request
  /// errors as proof (see `SyncEngine`).
  Future<void> connect(
    String addr, {
    Duration timeout = const Duration(seconds: 8),
  });

  /// Sends a request on the sync protocol and awaits the reply, or null
  /// when the peer is unreachable or times out (15 s).
  Future<Uint8List?> request(String peerId, Uint8List payload);

  /// Fetches a block by CID, asking [peerIds] in order. Null when nobody
  /// has it. Implementations try direct peer fetches before any Bitswap
  /// fallback.
  Future<Uint8List?> fetchBlock(String cid, List<String> peerIds);

  /// Stores [bytes] locally and returns its CID.
  Future<String> addData(Uint8List bytes);

  /// Reads a locally stored block by CID, or null when absent. Used for
  /// relay pushes without network traffic.
  Future<Uint8List?> localBlock(String cid);

  /// Handles incoming sync-protocol requests; the engine installs
  /// `SyncEngine.handleRequest` here at startup.
  /// See above.
  set onRequest(
    Future<Uint8List> Function(String from, Uint8List payload)? handler,
  );
}
