import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/ipfs/sync_manager.dart';
import '../core/storage/transaction_dao.dart' show TransactionData;
import '../models/transaction.dart';
import '../models/transaction_reversal.dart';
import '../services/transaction_service.dart';
import 'auth_provider.dart';
import 'group_provider.dart' show governanceServiceProvider;
import 'ipfs_provider.dart';
import 'data_version.dart';

final transactionServiceProvider = Provider<TransactionService>((ref) => TransactionService());

class TransactionListNotifier extends StateNotifier<AsyncValue<List<Transaction>>> {
  final Ref _ref;
  final TransactionService _service;
  final String groupId;
  StreamSubscription<SyncChange>? _changesSub;

  TransactionListNotifier(this._ref, this._service, this.groupId) : super(const AsyncValue.loading()) {
    loadTransactions();
    _changesSub = _ref.read(syncManagerProvider).changes.listen((change) {
      if (change.groupId == groupId &&
          (change.type == SyncChangeType.transaction || change.type == SyncChangeType.reversal)) {
        loadTransactions();
      }
    });
  }

  @override
  void dispose() {
    _changesSub?.cancel();
    super.dispose();
  }

  Future<void> loadTransactions() async {
    state = const AsyncValue.loading();
    try {
      state = AsyncValue.data(await _service.getByGroupId(groupId));
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Records a transaction authored by the current user (who must be an
  /// owner/admin) on behalf of [fromPeerId] → [toPeerId].
  Future<Transaction> createTransaction({
    required String fromPeerId,
    required String toPeerId,
    required TransactionType type,
    required double amount,
    String? note,
    String? loanId,
  }) async {
    final auth = _ref.read(authProvider.notifier);
    final identity = auth.requireIdentity();
    final keyPair = await auth.requireSigningKeyPair();

    final tx = await _service.createTransaction(
      groupId: groupId,
      authorPeerId: identity.peerId,
      authorKeyPair: keyPair,
      fromPeerId: fromPeerId,
      toPeerId: toPeerId,
      type: type,
      amount: amount,
      note: note,
      loanId: loanId,
    );
    await loadTransactions();
    bumpDataVersion(_ref);
    // Push it out right away if we're online; otherwise the periodic sync will.
    unawaited(_ref.read(syncManagerProvider).startManualSync());
    return tx;
  }

  Future<TransactionReversal> requestReversal(String transactionId, String reason) async {
    final auth = _ref.read(authProvider.notifier);
    final me = auth.requireIdentity().peerId;
    final kp = await auth.requireSigningKeyPair();
    final r = await _ref.read(governanceServiceProvider).requestReversal(
          groupId: groupId, actingPeerId: me, actingKeyPair: kp, transactionId: transactionId, reason: reason);
    unawaited(_ref.read(syncManagerProvider).publishReversal(r).catchError((_) => ''));
    return r;
  }

  Future<void> decideReversal(String reversalId, {required bool approve}) async {
    final auth = _ref.read(authProvider.notifier);
    final me = auth.requireIdentity().peerId;
    final kp = await auth.requireSigningKeyPair();
    final r = await _ref.read(governanceServiceProvider).decideReversal(
          groupId: groupId, actingPeerId: me, actingKeyPair: kp, reversalId: reversalId, approve: approve);
    unawaited(_ref.read(syncManagerProvider).publishReversal(r).catchError((_) => ''));
    await loadTransactions();
    bumpDataVersion(_ref);
  }

  Future<void> refresh() => loadTransactions();
}

final transactionListProvider =
    StateNotifierProvider.family<TransactionListNotifier, AsyncValue<List<Transaction>>, String>((ref, groupId) {
  return TransactionListNotifier(ref, ref.watch(transactionServiceProvider), groupId);
});

/// All transactions across groups (home "Transactions" tab).
final allTransactionsProvider = FutureProvider<List<Transaction>>((ref) async {
  ref.watch(syncTickProvider);
  return ref.watch(transactionServiceProvider).getAll();
});

/// Failed / queued rows for the Sync Status screen.
final failedTransactionsProvider = FutureProvider<List<TransactionData>>((ref) async {
  ref.watch(syncTickProvider);
  return ref.watch(transactionServiceProvider).getFailed();
});

final syncCountsProvider = FutureProvider<Map<String, int>>((ref) async {
  ref.watch(syncTickProvider);
  return ref.watch(transactionServiceProvider).syncCounts();
});

/// Increments on every sync state change / inbound change so dependent
/// FutureProviders refetch.
final syncTickProvider = StreamProvider<int>((ref) {
  final sm = ref.watch(syncManagerProvider);
  var n = 0;
  final controller = StreamController<int>();
  controller.add(n);
  final s1 = sm.stateStream.listen((_) => controller.add(++n));
  final s2 = sm.changes.listen((_) => controller.add(++n));
  ref.onDispose(() {
    s1.cancel();
    s2.cancel();
    controller.close();
  });
  return controller.stream;
});

final reversalsProvider = FutureProvider.family<List<TransactionReversal>, String>((ref, groupId) async {
  ref.watch(syncTickProvider);
  return ref.watch(governanceServiceProvider).reversalsForGroup(groupId);
});
