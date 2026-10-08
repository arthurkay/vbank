import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sync_coordinator.dart';

/// The sync coordinator, installed by the platform startup. Null in
/// widget tests, which never start a node: screens treat null as
/// "sync unavailable" and skip their post-write round.
final syncCoordinatorProvider = Provider<SyncCoordinator?>((ref) => null);

/// Engine state, starting with the current one. Unavailable without a
/// coordinator.
final syncStateProvider = StreamProvider<SyncState>((ref) async* {
  final SyncCoordinator? coordinator = ref.watch(syncCoordinatorProvider);
  if (coordinator == null) {
    return;
  }
  yield coordinator.state;
  await for (final SyncState state in coordinator.states) {
    yield state;
  }
});

/// Log events; each one rebuilds readers of [syncLogProvider].
final syncEventProvider = StreamProvider<SyncEvent>((ref) {
  final SyncCoordinator? coordinator = ref.watch(syncCoordinatorProvider);
  if (coordinator == null) {
    return const Stream.empty();
  }
  return coordinator.log;
});

/// Relay addresses in force (built-in plus user-added).
final relayListProvider = FutureProvider<List<String>>((ref) async {
  final SyncCoordinator? coordinator = ref.watch(syncCoordinatorProvider);
  if (coordinator == null) {
    return const [];
  }
  return coordinator.relayAddresses();
});
