import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/transaction.dart';
import '../../models/transaction_reversal.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../ui/ui.dart';

/// DESIGN_PLAN §27 transaction_detail + reversal_request screens.
class TransactionDetailScreen extends ConsumerStatefulWidget {
  final Transaction transaction;
  const TransactionDetailScreen({super.key, required this.transaction});

  @override
  ConsumerState<TransactionDetailScreen> createState() => _TransactionDetailScreenState();
}

class _TransactionDetailScreenState extends ConsumerState<TransactionDetailScreen> {
  bool _busy = false;

  void _msg(String m, {bool error = false}) {
    if (mounted) showMessage(context, m, error: error);
  }

  Future<void> _requestReversal() async {
    final reason = await promptSheet(
      context,
      title: 'Request reversal',
      message: 'An admin has to approve the reversal before the transaction is undone.',
      label: 'Reason',
      hint: 'e.g. recorded twice',
      maxLines: 3,
      confirmLabel: 'Request',
    );
    if (reason == null || reason.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await ref.read(transactionListProvider(widget.transaction.groupId).notifier)
          .requestReversal(widget.transaction.id, reason.trim());
      ref.invalidate(reversalsProvider(widget.transaction.groupId));
      _msg('Reversal requested — an admin must approve it');
    } catch (e) {
      _msg('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _decide(TransactionReversal r, bool approve) async {
    if (approve) {
      final ok = await confirmSheet(
        context,
        title: 'Reverse this transaction?',
        message: 'A compensating record is written and the original is marked reversed. This is kept in the history.',
        confirmLabel: 'Reverse',
        destructive: true,
      );
      if (!ok) return;
    }
    setState(() => _busy = true);
    try {
      await ref.read(transactionListProvider(widget.transaction.groupId).notifier)
          .decideReversal(r.id, approve: approve);
      ref.invalidate(reversalsProvider(widget.transaction.groupId));
      _msg(approve ? 'Transaction reversed' : 'Reversal rejected');
      if (approve && mounted) Navigator.pop(context);
    } catch (e) {
      _msg('$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tx = widget.transaction;
    final group = ref.watch(selectedGroupProvider);
    final me = ref.watch(authProvider).identity?.peerId;
    final canWrite = ref.watch(canWriteProvider);
    final reversals = (ref.watch(reversalsProvider(tx.groupId)).value ?? const <TransactionReversal>[])
        .where((r) => r.originalTransactionId == tx.id)
        .toList();
    final pending = reversals.where((r) => r.isPending).firstOrNull;
    final currency = group?.config.currency ?? tx.currency;

    String nameOf(String peerId) =>
        peerId == 'group' ? 'Group fund' : group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? peerId;

    final involved = tx.fromPeerId == me || tx.toPeerId == me;
    final canRequest = tx.status == TransactionStatus.confirmed && pending == null && (involved || canWrite);
    final reversed = tx.status == TransactionStatus.reversed;

    return AppPage(
      title: 'Transaction',
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Panel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        fmtMoney(currency, tx.amount),
                        style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null),
                      ).x2Large.bold,
                    ),
                    StatusBadge(
                      tx.status.name,
                      tone: reversed
                          ? StatusTone.destructive
                          : tx.status == TransactionStatus.confirmed
                              ? StatusTone.primary
                              : StatusTone.neutral,
                    ),
                  ],
                ),
                const Gap(12),
                InfoRow('Type', tx.type.name),
                InfoRow('From', nameOf(tx.fromPeerId)),
                InfoRow('To', nameOf(tx.toPeerId)),
                InfoRow('Recorded by', nameOf(tx.authorPeerId)),
                InfoRow('When', fmtDateTime(tx.timestamp)),
                if (tx.note != null && tx.note!.isNotEmpty) InfoRow('Note', tx.note!),
                InfoRow('Sequence', '#${tx.sequenceNumber}'),
                InfoRow('ID', tx.id),
              ],
            ),
          ),
          const Gap(12),
          if (canRequest)
            Button.outline(
              onPressed: _busy ? null : _requestReversal,
              leading: const Icon(LucideIcons.undo2),
              child: const Text('Request reversal'),
            ),
          if (reversals.isNotEmpty) ...[
            const SectionTitle('Reversal requests'),
            for (final r in reversals)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Panel(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text('by ${nameOf(r.requestedByPeerId)}').semiBold),
                          StatusBadge(
                            r.status.name,
                            tone: r.isPending
                                ? StatusTone.neutral
                                : r.status.name == 'approved'
                                    ? StatusTone.primary
                                    : StatusTone.destructive,
                          ),
                        ],
                      ),
                      const Gap(6),
                      Text(r.reason),
                      if (r.approvedByPeerId != null) ...[
                        const Gap(4),
                        Text('Decided by ${nameOf(r.approvedByPeerId!)}').small.muted,
                      ],
                      if (r.isPending && canWrite && r.requestedByPeerId != me) ...[
                        const Gap(12),
                        Row(
                          children: [
                            Button.primary(
                              onPressed: _busy ? null : () => _decide(r, true),
                              child: const Text('Approve reversal'),
                            ),
                            const Gap(8),
                            Button.ghost(
                              onPressed: _busy ? null : () => _decide(r, false),
                              child: const Text('Reject'),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
