import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group.dart';
import '../../providers/group_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/transaction_tile.dart';
import 'transaction_detail_screen.dart';

/// All transactions across the user's groups, newest first.
class TransactionListScreen extends ConsumerWidget {
  const TransactionListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(allTransactionsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];
    return AppPage(
      title: 'Transactions',
      child: txs.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (list) {
          if (list.isEmpty) return const EmptyState(icon: LucideIcons.receipt, title: 'No transactions yet');
          return RefreshTrigger(
            onRefresh: () => ref.refresh(allTransactionsProvider.future),
            child: ListView.builder(
              padding: const EdgeInsets.all(20),
              itemCount: list.length,
              itemBuilder: (context, i) {
                final tx = list[i];
                final group = groups.where((g) => g.id == tx.groupId).firstOrNull;
                return TransactionTile(
                  transaction: tx,
                  onTap: () {
                    if (group != null) ref.read(selectedGroupProvider.notifier).state = group;
                    pushScreen(context, TransactionDetailScreen(transaction: tx));
                  },
                );
              },
            ),
          );
        },
      ),
    );
  }
}
