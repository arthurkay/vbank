import '../models/group.dart';
import '../models/loan.dart';
import '../models/loan_progress.dart';
import '../models/transaction.dart';
import '../ui/ui.dart';

String loanStatusLabel(LoanStatus s) => switch (s) {
      LoanStatus.pending => 'Awaiting approval',
      LoanStatus.approved => 'Approved · not yet paid out',
      LoanStatus.disbursed => 'Paid out',
      LoanStatus.repaying => 'Repaying',
      LoanStatus.completed => 'Fully repaid',
      LoanStatus.rejected => 'Rejected',
      LoanStatus.defaulted => 'Defaulted',
    };

StatusTone loanStatusTone(LoanStatus s) => switch (s) {
      LoanStatus.pending => StatusTone.neutral,
      LoanStatus.approved || LoanStatus.disbursed || LoanStatus.repaying => StatusTone.primary,
      LoanStatus.completed => StatusTone.secondary,
      LoanStatus.rejected || LoanStatus.defaulted => StatusTone.destructive,
    };

String memberName(Group? group, String peerId) =>
    group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? 'Unknown member';

/// One loan in a list: who, how much, status, and how much has come back.
class LoanTile extends StatelessWidget {
  final LoanRequest loan;
  final Group group;
  final LoanProgress? progress;
  final VoidCallback? onTap;
  const LoanTile({super.key, required this.loan, required this.group, this.progress, this.onTap});

  @override
  Widget build(BuildContext context) {
    final c = group.config.currency;
    final p = progress;
    final showProgress = p != null && p.totalDue > 0;
    return ListRow(
      onTap: onTap,
      title: Text('${fmtMoney(c, p?.borrowed ?? loan.requestedAmount)} · ${memberName(group, loan.borrowerPeerId)}'),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            showProgress
                ? 'Repaid ${fmtMoney(c, p.repaid)} of ${fmtMoney(c, p.totalDue)} · ${loan.termWeeks} weeks'
                : '${loanStatusLabel(loan.status)} · ${loan.termWeeks} weeks',
          ).small.muted,
          if (showProgress) ...[const Gap(8), ProgressBar(value: p.fraction)],
        ],
      ),
      trailing: StatusBadge(loanStatusLabel(loan.status).split(' ').first, tone: loanStatusTone(loan.status)),
    );
  }
}

/// Borrowed / repaid / remaining with a progress bar — the loan's headline.
class LoanProgressView extends StatelessWidget {
  final LoanProgress progress;
  final String currency;
  const LoanProgressView({super.key, required this.progress, required this.currency});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Three figures side by side: the currency goes in the caption so the
        // numbers stay on one line on a phone.
        Row(
          children: [
            Expanded(child: Metric(label: 'Borrowed', value: p.borrowed.toStringAsFixed(2))),
            Expanded(child: Metric(label: 'Repaid', value: p.repaid.toStringAsFixed(2), align: CrossAxisAlignment.center)),
            Expanded(child: Metric(label: 'Still owed', value: p.remaining.toStringAsFixed(2), align: CrossAxisAlignment.end)),
          ],
        ),
        const Gap(12),
        ProgressBar(value: p.fraction),
        const Gap(6),
        Opacity(
          opacity: 0.7,
          child: Text(
            p.totalDue > 0
                ? '$currency · ${(p.fraction * 100).round()}% of ${fmtMoney(currency, p.totalDue)} repaid (incl. interest)'
                : 'Not yet approved',
          ).xSmall,
        ),
      ],
    );
  }
}

/// The repayments recorded against a loan, newest first.
class RepaymentList extends StatelessWidget {
  final List<Transaction> repayments;
  final Group? group;
  final String currency;
  const RepaymentList({super.key, required this.repayments, required this.group, required this.currency});

  @override
  Widget build(BuildContext context) {
    if (repayments.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: const Text('No repayments yet').small.muted);
    }
    final newestFirst = repayments.reversed.toList();
    return Column(
      children: [
        for (final t in newestFirst)
          ListRow(
            leading: const Icon(LucideIcons.repeat),
            title: Text(fmtMoney(currency, t.amount)),
            subtitle: Text('${fmtDate(t.timestamp)} · recorded by ${memberName(group, t.authorPeerId)}').small.muted,
          ),
      ],
    );
  }
}
