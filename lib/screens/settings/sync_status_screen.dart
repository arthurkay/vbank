import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/relay/relay_directory.dart';
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
          _RelayPanel(),
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


/// Always-on relay nodes (see deploy/relay/README.md): the way members on
/// different networks reach each other.
class _RelayPanel extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final relays = ref.watch(relayAddressesProvider).value ?? const <String>[];
    final builtIn = ref.watch(builtInRelayProvider).value ?? (enabled: true, addrs: const <String>[]);
    final sm = ref.read(syncManagerProvider);
    Future<void> add() async {
      final addr = await promptSheet(
        context,
        title: 'Relay server',
        message: 'Paste the address printed by the relay, e.g. /ip4/203.0.113.7/tcp/4001/p2p/12D3KooW…. '
            'Members on other networks reach each other through it. It never holds your group passphrase.',
        label: 'Address',
        hint: '/ip4/…/tcp/4001/p2p/…',
        confirmLabel: 'Add',
      );
      if (addr == null || addr.trim().isEmpty || !context.mounted) return;
      if (!addr.contains('/p2p/')) {
        showMessage(context, 'That is not a relay address (it should end in /p2p/<peer id>)', error: true);
        return;
      }
      await sm.addRelays([addr.trim()]);
      ref.invalidate(relayAddressesProvider);
      unawaited(sm.startManualSync());
    }
    return Panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: const Text('Relay server').semiBold),
              Button.ghost(onPressed: add, leading: const Icon(LucideIcons.plus, size: 16), child: const Text('Add')),
            ],
          ),
          const Gap(4),
          Row(
            children: [
              const Icon(LucideIcons.server, size: 16),
              const Gap(8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('vBank relay · ${kBuiltInRelayHosts.first}').small,
                    Text(
                      !builtIn.enabled
                          ? 'Off'
                          : builtIn.addrs.isEmpty
                              ? 'Looking up its address…'
                              : 'On · ${builtIn.addrs.first.split('/p2p/').last.substring(0, 12)}…',
                    ).xSmall.muted,
                  ],
                ),
              ),
              Switch(
                value: builtIn.enabled,
                onChanged: (v) async {
                  await sm.setBuiltInRelayEnabled(v);
                  ref.invalidate(builtInRelayProvider);
                  if (v) unawaited(sm.startManualSync());
                },
              ),
            ],
          ),
          if (relays.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text('Add your own relay if your group runs one; the built-in one works for everyone.'),
            ).small.muted
          else
            for (final r in relays)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Row(
                  children: [
                    const Icon(LucideIcons.server, size: 16),
                    const Gap(8),
                    Expanded(child: Text(r, maxLines: 2, overflow: TextOverflow.ellipsis).xSmall),
                    IconButton.ghost(
                      icon: const Icon(LucideIcons.x, size: 16),
                      onPressed: () async {
                        await sm.removeRelay(r);
                        ref.invalidate(relayAddressesProvider);
                      },
                    ),
                  ],
                ),
              ),
        ],
      ),
    );
  }
}
