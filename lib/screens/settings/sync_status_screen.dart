import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/ipfs/sync_manager.dart';
import '../../core/storage/transaction_dao.dart' as q;
import '../../providers/ipfs_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/sync_status_indicator.dart';

/// DESIGN_PLAN §27 sync_status_screen + §21 offline queue: node/sync state,
/// queue counts, failed transactions with manual retry, and the sync log.
class SyncStatusScreen extends ConsumerWidget {
  const SyncStatusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = ref.watch(ipfsNodeStateProvider).value ?? ref.read(ipfsServiceProvider).state;
    final sync = ref.watch(syncStateProvider).value ?? ref.read(syncManagerProvider).state;
    final counts = ref.watch(syncCountsProvider).value ?? const {};
    final failed = ref.watch(failedTransactionsProvider).value ?? const <q.TransactionData>[];
    final log = ref.watch(syncLogProvider).value ?? const <SyncEvent>[];
    final sm = ref.read(syncManagerProvider);
    final peerId = ref.read(ipfsServiceProvider).peerId;
    final scheme = Theme.of(context).colorScheme;

    return AppPage(
      title: 'Sync Status',
      trailing: [
        IconButton.ghost(
          icon: const Icon(LucideIcons.refreshCw),
          onPressed: sync == SyncState.syncing ? null : () => sm.startManualSync(),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: const Text('Network').semiBold),
                    SyncStatusIndicator(status: syncStatusFrom(node, sync)),
                  ],
                ),
                const Gap(8),
                InfoRow('Node', node.name),
                InfoRow('Sync', sync.name),
                if (sm.lastSyncTime != null) InfoRow('Last sync', fmtDateTime(sm.lastSyncTime!)),
                if (sm.lastError != null) InfoRow('Last error', sm.lastError!),
                if (peerId != null) InfoRow('Peer ID', peerId),
              ],
            ),
          ),
          const Gap(12),
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Transaction queue').semiBold,
                const Gap(8),
                InfoRow('Queued', '${counts[q.SyncStatus.queued] ?? 0}'),
                InfoRow('Syncing', '${counts[q.SyncStatus.syncing] ?? 0}'),
                InfoRow('Synced', '${counts[q.SyncStatus.synced] ?? 0}'),
                InfoRow('Failed', '${counts[q.SyncStatus.failed] ?? 0}'),
              ],
            ),
          ),
          if (failed.isNotEmpty) ...[
            SectionTitle('Failed after ${q.SyncStatus.maxAttempts} attempts'),
            for (final t in failed)
              ListRow(
                leading: Icon(LucideIcons.circleAlert, color: scheme.destructive),
                title: Text('${t.type} ${t.currency} ${t.amount.toStringAsFixed(2)}'),
                subtitle: Text(t.lastSyncError ?? 'Unknown error', maxLines: 2, overflow: TextOverflow.ellipsis).small.muted,
                trailing: Button.outline(
                  onPressed: () async {
                    await ref.read(transactionServiceProvider).retry(t.id);
                    await sm.startManualSync();
                    ref.invalidate(failedTransactionsProvider);
                    ref.invalidate(syncCountsProvider);
                  },
                  child: const Text('Retry'),
                ),
              ),
          ],
          const SectionTitle('Activity log'),
          if (log.isEmpty) const Text('Nothing yet').muted,
          for (final e in log.take(100))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Basic(
                leading: Icon(
                  switch (e.type) { SyncEventType.error => LucideIcons.circleAlert, SyncEventType.warning => LucideIcons.triangleAlert, _ => LucideIcons.circleCheck },
                  size: 18,
                  color: switch (e.type) { SyncEventType.error => scheme.destructive, SyncEventType.warning => VBankTheme.warning(context), _ => scheme.primary },
                ),
                title: Text(e.message).small,
                subtitle: Text(fmtDateTime(e.timestamp)).xSmall.muted,
              ),
            ),
        ],
      ),
    );
  }
}
