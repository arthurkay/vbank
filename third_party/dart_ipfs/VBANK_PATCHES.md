# vBank patches to dart_ipfs 1.11.7

Vendored copy of `dart_ipfs` 1.11.7 from pub.dev (MIT), used via
`dependency_overrides` in the root `pubspec.yaml`.

1. `lib/src/core/ipfs_node/network_handler_io.dart` — construct the router with
   `seed: _config.libp2pIdentitySeed`. Upstream declares
   `IPFSConfig.libp2pIdentitySeed` but never passes it on, so every start minted
   a new peer id and every address other members had for this node went stale.
   vBank stores a random 32-byte seed next to the datastore and passes it here.

2. `lib/src/transport/libp2p_router.dart` — the inbound stream handler awaits a
   protocol handler that returns a `Future` before reading the next message.
   Upstream fires the handler and immediately reads again; an empty read is
   treated as end-of-stream and the stream is closed, so a reply written by an
   async handler (our `/vbank/fetch` and `/vbank/sync` responders) hit a closed
   stream and the requester saw an instant empty reply.

3. `lib/src/transport/libp2p_router.dart` — addresses learned through
   `connect()` stay in the peer store for 24 h instead of 10 min. After the
   TTL every `newStream` to a still-connected peer failed with "No addresses
   found for peer". Also adds an opt-in `Libp2pRouter.debugLog` that prints
   dial/stream failures (the package logger is silent at the app's log level).

4. `lib/src/transport/libp2p_router.dart` — `sendMessage`/`sendRequest` open
   their stream through `_openStreamWithRetry`: on failure the peer's
   connections are closed and its last known address redialed once. The swarm
   otherwise keeps a connection whose remote silently went away (an app
   restart) and every `newStream` on it fails while `connect()` still reports
   success.
