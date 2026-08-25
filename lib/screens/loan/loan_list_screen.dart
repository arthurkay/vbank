import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group.dart';
import '../../models/loan.dart';
import '../../providers/group_provider.dart';
import '../../providers/loan_provider.dart';
import '../../ui/ui.dart';
import 'loan_detail_screen.dart';

/// Loans of the selected group.
class LoanListScreen extends ConsumerWidget {
  const LoanListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(selectedGroupProvider);
    if (group == null) {
      return const AppPage(title: 'Loans', child: EmptyState(icon: LucideIcons.landmark, title: 'No group selected'));
    }
    final loans = ref.watch(loanListProvider(group.id));
    final c = group.config.currency;
    return AppPage(
      title: '${group.name} · loans',
      floating: group.status == GroupStatus.dissolved
          ? null
          : Button.primary(
              onPressed: () => Navigator.pushNamed(context, '/request-loan'),
              leading: const Icon(LucideIcons.plus),
              child: const Text('Request'),
            ),
      child: loans.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (list) {
          if (list.isEmpty) return const EmptyState(icon: LucideIcons.landmark, title: 'No loans yet');
          String borrowerOf(LoanRequest l) =>
              group.members.where((m) => m.peerId == l.borrowerPeerId).firstOrNull?.name ?? 'member';
          return FilterableList<LoanRequest>(
            items: list,
            searchPlaceholder: 'Search loans',
            searchText: (l) =>
                '${borrowerOf(l)} ${l.status.name} ${l.requestedAmount.toStringAsFixed(2)} ${l.termWeeks} weeks ${l.reason ?? ''}',
            filters: [
              FilterOption.all<LoanRequest>(),
              FilterOption('Pending', (l) => l.status == LoanStatus.pending),
              FilterOption('Active', (l) => l.isActive),
              FilterOption('Completed', (l) => l.status == LoanStatus.completed),
              FilterOption('Rejected', (l) => l.status == LoanStatus.rejected || l.status == LoanStatus.defaulted),
            ],
            builder: (context, visible) => ListView(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            children: [
              for (final loan in visible)
                ListRow(
                  title: Text('${fmtMoney(c, loan.requestedAmount)} · ${group.members.where((m) => m.peerId == loan.borrowerPeerId).firstOrNull?.name ?? 'member'}'),
                  subtitle: Text(loan.status.name).small.muted,
                  trailing: Icon(loan.status == LoanStatus.pending ? LucideIcons.clock : LucideIcons.chevronRight),
                  onTap: () => pushScreen(context, LoanDetailScreen(loanId: loan.id)),
                ),
            ],
            ),
          );
        },
      ),
    );
  }
}
