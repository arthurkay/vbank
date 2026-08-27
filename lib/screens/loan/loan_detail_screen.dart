import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/loan.dart';
import '../../models/repayment_schedule.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/loan_provider.dart';
import '../../ui/ui.dart';
import '../../widgets/loan_tile.dart';

/// DESIGN_PLAN §15 / §27 loan_detail + approve_loan + repayment screens.
class LoanDetailScreen extends ConsumerStatefulWidget {
  final String loanId;
  const LoanDetailScreen({super.key, required this.loanId});

  @override
  ConsumerState<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends ConsumerState<LoanDetailScreen> {
  bool _busy = false;

  Future<void> _run(Future<void> Function() action, String ok) async {
    setState(() => _busy = true);
    try {
      await action();
      if (mounted) showMessage(context, ok);
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<double?> _askAmount(String title, double initial, {String? hint, String confirm = 'OK'}) async {
    final text = await promptSheet(
      context,
      title: title,
      message: hint,
      label: 'Amount',
      initial: initial.toStringAsFixed(2),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      confirmLabel: confirm,
    );
    if (text == null) return null;
    final v = double.tryParse(text);
    if (v == null || v <= 0) {
      if (mounted) showMessage(context, 'Enter a valid amount', error: true);
      return null;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(selectedGroupProvider);
    final loanAsync = ref.watch(loanProvider(widget.loanId));
    final scheduleAsync = ref.watch(loanScheduleProvider(widget.loanId));
    final progress = ref.watch(loanProgressProvider(widget.loanId)).value;
    final canWrite = ref.watch(canWriteProvider);
    final me = ref.watch(authProvider).identity?.peerId;
    final scheme = Theme.of(context).colorScheme;

    return AppPage(
      title: 'Loan',
      child: loanAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(e),
        data: (loan) {
          if (loan == null || group == null) {
            return const EmptyState(icon: LucideIcons.landmark, title: 'Loan not found');
          }
          final borrower = group.members.where((m) => m.peerId == loan.borrowerPeerId).firstOrNull;
          final currency = group.config.currency;
          final notifier = ref.read(loanListProvider(group.id).notifier);
          final isBorrower = me == loan.borrowerPeerId;

          final borrowerName = borrower?.name ?? 'Unknown member';
          final settled = loan.status == LoanStatus.completed;
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              // The loan as a ticket: who and how much on top, repayment
              // progress below the perforation.
              HeroCard(
                body: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Metric(
                        label: '${loan.approvedAmount > 0 ? 'Loan to' : 'Requested by'} $borrowerName',
                        value: fmtMoney(currency, progress?.borrowed ?? loan.requestedAmount),
                        large: true,
                      ),
                    ),
                    const Gap(12),
                    Opacity(opacity: 0.85, child: OutlineBadge(child: Text(loanStatusLabel(loan.status)))),
                  ],
                ),
                footer: progress == null || progress.totalDue <= 0
                    ? Row(
                        children: [
                          Expanded(child: Metric(label: 'Term', value: '${loan.termWeeks} weeks')),
                          Expanded(
                            child: Metric(
                              label: 'Interest',
                              value: '${(loan.interestRate * 100).toStringAsFixed(0)}%',
                              align: CrossAxisAlignment.end,
                            ),
                          ),
                        ],
                      )
                    : LoanProgressView(progress: progress, currency: currency),
              ),
              const Gap(16),
              if (canWrite) ...[
                if (loan.status == LoanStatus.pending && !isBorrower) ...[
                  Button.primary(
                    onPressed: _busy
                        ? null
                        : () async {
                            final amt = await _askAmount('Approve loan', loan.requestedAmount,
                                hint: 'Up to ${fmtMoney(currency, loan.requestedAmount)}', confirm: 'Approve');
                            if (amt == null) return;
                            await _run(() => notifier.approveLoan(loanId: loan.id, approvedAmount: amt), 'Loan approved');
                          },
                    leading: const Icon(LucideIcons.check),
                    child: const Text('Approve'),
                  ),
                  const Gap(8),
                  Button.outline(
                    onPressed: _busy
                        ? null
                        : () async {
                            final ok = await confirmSheet(context,
                                title: 'Reject this loan?', message: 'The borrower will see the request as rejected.',
                                confirmLabel: 'Reject', destructive: true);
                            if (ok) await _run(() => notifier.rejectLoan(loanId: loan.id), 'Loan rejected');
                          },
                    leading: const Icon(LucideIcons.x),
                    child: const Text('Reject'),
                  ),
                ],
                if (loan.status == LoanStatus.pending && isBorrower)
                  const Alert(
                    leading: Icon(LucideIcons.info),
                    content: Text('Another admin must approve your own loan request.'),
                  ),
                if (loan.status == LoanStatus.approved)
                  Button.primary(
                    onPressed: _busy
                        ? null
                        : () => _run(() => notifier.disburseLoan(loanId: loan.id), 'Loan disbursed — repayment schedule created'),
                    leading: const Icon(LucideIcons.banknote),
                    child: const Text('Record disbursement'),
                  ),
                if (loan.isActive)
                  Button.primary(
                    onPressed: _busy
                        ? null
                        : () async {
                            final sched = scheduleAsync.value ?? const <RepaymentSchedule>[];
                            final next = sched.where((s) => !s.isPaid).firstOrNull;
                            final suggested = next == null ? loan.weeklyPayment : next.remainingAmount + next.penalty;
                            final amt = await _askAmount('Record repayment', suggested, confirm: 'Record');
                            if (amt == null) return;
                            await _run(() => notifier.recordRepayment(loanId: loan.id, amount: amt), 'Repayment recorded');
                          },
                    leading: const Icon(LucideIcons.creditCard),
                    child: const Text('Record repayment'),
                  ),
                const Gap(12),
              ],
              if (progress != null && (progress.repayments.isNotEmpty || loan.isActive || settled)) ...[
                SectionTitle('Repayments', trailing: Text('${progress.repayments.length}').xSmall.muted),
                RepaymentList(repayments: progress.repayments, group: group, currency: currency),
              ],
              const SectionTitle('Details'),
              Panel(
                child: Column(
                  children: [
                    InfoRow('Borrower', borrowerName),
                    InfoRow('Requested', fmtMoney(currency, loan.requestedAmount)),
                    if (loan.approvedAmount > 0) InfoRow('Approved', fmtMoney(currency, loan.approvedAmount)),
                    InfoRow('Term', '${loan.termWeeks} weeks'),
                    InfoRow('Interest', '${(loan.interestRate * 100).toStringAsFixed(0)}%'),
                    if (loan.approvedAmount > 0) InfoRow('Total due', fmtMoney(currency, loan.totalWithInterest)),
                    if (loan.reason != null && loan.reason!.isNotEmpty) InfoRow('Reason', loan.reason!),
                    InfoRow('Requested on', fmtDateTime(loan.requestedAt)),
                    if (loan.approvedByPeerId != null) InfoRow('Approved by', memberName(group, loan.approvedByPeerId!)),
                    if (loan.disbursedAt != null) InfoRow('Paid out', fmtDateTime(loan.disbursedAt!)),
                    if (loan.completedAt != null) InfoRow('Settled', fmtDateTime(loan.completedAt!)),
                  ],
                ),
              ),
              if (loan.isActive || loan.status == LoanStatus.completed || loan.status == LoanStatus.defaulted) ...[
                const SectionTitle('Repayment schedule'),
                scheduleAsync.when(
                  loading: () => const LoadingView(),
                  error: (e, _) => ErrorView(e),
                  data: (schedule) => Column(
                    children: [
                      for (final s in schedule)
                        ListRow(
                          leading: Icon(
                            s.isPaid
                                ? LucideIcons.circleCheck
                                : s.isOverdue
                                    ? LucideIcons.triangleAlert
                                    : LucideIcons.clock,
                            color: s.isPaid
                                ? scheme.primary
                                : s.isOverdue
                                    ? scheme.destructive
                                    : scheme.mutedForeground,
                          ),
                          title: Text('Instalment ${s.installmentNumber} · ${fmtMoney(currency, s.expectedAmount)}'),
                          subtitle: Text(
                            'Due ${fmtDate(s.dueDate)}'
                            '${s.paidAmount > 0 ? ' · paid ${fmtMoney(currency, s.paidAmount)}' : ''}'
                            '${s.penalty > 0 ? ' · penalty ${fmtMoney(currency, s.penalty)}' : ''}',
                          ).small.muted,
                          trailing: Text(s.status.label).small,
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
