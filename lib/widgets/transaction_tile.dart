import 'package:shadcn_flutter/shadcn_flutter.dart';
import '../models/group.dart';
import '../models/transaction.dart';
import '../ui/ui.dart' show ListRow, VBankTheme, fmtDate;

class TransactionTile extends StatelessWidget {
  final Transaction transaction;
  final VoidCallback? onTap;

  /// The transaction's group, used to name the member the money came from
  /// (or went to) and, when [showGroup] is set, the group itself — the
  /// cross-group Activity list needs both to be readable.
  final Group? group;
  final bool showGroup;

  const TransactionTile({super.key, required this.transaction, this.onTap, this.group, this.showGroup = false});

  /// "Contribution from Grace", "Loan to Grace", "Repayment from Grace"…
  static String headline(Transaction tx, Group? group) {
    String nameOf(String peerId) =>
        group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? (peerId == 'group' ? 'the group fund' : 'a member');
    final type = '${tx.type.name[0].toUpperCase()}${tx.type.name.substring(1)}';
    return switch (tx.type) {
      TransactionType.contribution || TransactionType.repayment || TransactionType.penalty || TransactionType.fee =>
        '$type from ${nameOf(tx.fromPeerId)}',
      TransactionType.loan || TransactionType.withdrawal => '$type to ${nameOf(tx.toPeerId)}',
      TransactionType.reversal => type,
    };
  }

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
    final title = headline(tx, group);
    final details = [
      if (showGroup && group != null) group!.name,
      fmtDate(tx.timestamp),
      if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
    ].join(' · ');
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
      subtitle: Text(details).small.muted,
      trailing: Text(
        '${tx.currency} ${tx.amount.toStringAsFixed(2)}',
        style: TextStyle(decoration: reversed ? TextDecoration.lineThrough : null),
      ).semiBold,
    );
  }
}
