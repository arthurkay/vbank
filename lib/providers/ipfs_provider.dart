import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ipfs/ipfs_service.dart';
import '../core/ipfs/pending_join.dart';
import '../core/ipfs/sync_manager.dart';
import 'data_version.dart';
import 'group_provider.dart';
import 'loan_provider.dart' show loanServiceProvider;
import 'meeting_provider.dart' show meetingServiceProvider;
import 'transaction_provider.dart' show transactionServiceProvider, syncTickProvider;

final ipfsServiceProvider = Provider<IpfsService>((ref) {
  final service = IpfsService();
  ref.onDispose(() => service.dispose());
  return service;
});

final syncManagerProvider = Provider<SyncManager>((ref) {
  final manager = SyncManager(
    ipfsService: ref.watch(ipfsServiceProvider),
    transactionService: ref.watch(transactionServiceProvider),
    groupService: ref.watch(groupServiceProvider),
    groupKeyService: ref.watch(groupKeyServiceProvider),
    loanService: ref.watch(loanServiceProvider),
    meetingService: ref.watch(meetingServiceProvider),
    governanceService: ref.watch(governanceServiceProvider),
    inviteService: ref.watch(inviteServiceProvider),
  );
  ref.onDispose(() => manager.dispose());
  return manager;
});

/// Node state, seeded with the *current* value so late subscribers (screens
/// built after the node already changed state) don't sit in `loading`.
final ipfsNodeStateProvider = StreamProvider<IpfsNodeState>((ref) {
  final ipfsService = ref.watch(ipfsServiceProvider);
  return () async* {
    yield ipfsService.state;
    yield* ipfsService.stateStream;
  }();
});

final syncStateProvider = StreamProvider<SyncState>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return () async* {
    yield syncManager.state;
    yield* syncManager.stateStream;
  }();
});

/// Live sync log (most recent first), for the Sync Status screen.
final syncLogProvider = StreamProvider<List<SyncEvent>>((ref) {
  final syncManager = ref.watch(syncManagerProvider);
  return () async* {
    yield syncManager.recentLog;
    await for (final _ in syncManager.syncLogStream) {
      yield syncManager.recentLog;
    }
  }();
});

/// Joins waiting for a member of the group to come online (see PendingJoin).
final pendingJoinsProvider = FutureProvider<List<PendingJoin>>((ref) {
  ref.watch(syncTickProvider);
  ref.watch(dataVersionProvider);
  return ref.watch(syncManagerProvider).pendingJoins();
});
