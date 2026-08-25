import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/loan.dart';
import '../../models/repayment_schedule.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/loan_provider.dart';
import '../../ui/ui.dart';

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

  static StatusTone _tone(LoanStatus s) => switch (s) {
        LoanStatus.pending => StatusTone.neutral,
        LoanStatus.approved || LoanStatus.disbursed || LoanStatus.repaying => StatusTone.primary,
        LoanStatus.completed => StatusTone.secondary,
        LoanStatus.rejected || LoanStatus.defaulted => StatusTone.destructive,
      };

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(selectedGroupProvider);
    final loanAsync = ref.watch(loanProvider(widget.loanId));
    final scheduleAsync = ref.watch(loanScheduleProvider(widget.loanId));
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

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(child: Text(fmtMoney(currency, loan.requestedAmount)).x2Large.bold),
                        StatusBadge(loan.status.name, tone: _tone(loan.status)),
                      ],
                    ),
                    const Gap(12),
                    InfoRow('Borrower', borrower?.name ?? loan.borrowerPeerId),
                    InfoRow('Term', '${loan.termWeeks} weeks'),
                    InfoRow('Interest', '${(loan.interestRate * 100).toStringAsFixed(0)}%'),
                    if (loan.approvedAmount > 0) InfoRow('Approved', fmtMoney(currency, loan.approvedAmount)),
                    if (loan.approvedAmount > 0) InfoRow('Total due', fmtMoney(currency, loan.totalWithInterest)),
                    if (loan.reason != null && loan.reason!.isNotEmpty) InfoRow('Reason', loan.reason!),
                    InfoRow('Requested', fmtDateTime(loan.requestedAt)),
                    if (loan.disbursedAt != null) InfoRow('Disbursed', fmtDateTime(loan.disbursedAt!)),
                    if (loan.completedAt != null) InfoRow('Completed', fmtDateTime(loan.completedAt!)),
                  ],
                ),
              ),
              const Gap(12),
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
                          title: Text('Installment ${s.installmentNumber} — ${fmtMoney(currency, s.expectedAmount)}'),
                          subtitle: Text(
                            'Due ${fmtDate(s.dueDate)}'
                            '${s.paidAmount > 0 ? ' · paid ${s.paidAmount.toStringAsFixed(2)}' : ''}'
                            '${s.penalty > 0 ? ' · penalty ${s.penalty.toStringAsFixed(2)}' : ''}',
                          ).small.muted,
                          trailing: Text(s.status.name).small,
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
