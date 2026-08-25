import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../models/transaction.dart';
import '../ui/ui.dart' show ListRow, VBankTheme, fmtDate;

class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onTap;
  const TransactionTile({super.key, required this.transaction, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final tx = transaction;
    final (icon, color) = switch (tx.type) {
      TransactionType.contribution => (LucideIcons.piggyBank, scheme.primary),
      TransactionType.loan => (LucideIcons.landmark, scheme.chart2),
      TransactionType.repayment => (LucideIcons.repeat, scheme.primary),
      TransactionType.withdrawal => (LucideIcons.banknote, scheme.chart3),
      TransactionType.penalty || TransactionType.fee => (LucideIcons.gavel, VBankTheme.warning(context)),
      TransactionType.reversal => (LucideIcons.undo2, scheme.destructive),
    };
    final reversed = tx.status == TransactionStatus.reversed;
    final title = '${tx.type.name[0].toUpperCase()}${tx.type.name.substring(1)}';
    return ListRow(
      onTap: onTap,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: color),
      ),
      title: Text(reversed ? '$title (reversed)' : title),
      subtitle: Text('${fmtDate(tx.timestamp)}${tx.note != null && tx.note!.isNotEmpty ? ' · ${tx.note}' : ''}').small.muted,
      trailing: Text(
        '${tx.currency} ${tx.amount.toStringAsFixed(2)}',
        style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null),
      ).semiBold,
    );
  }
}
