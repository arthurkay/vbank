import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/core/failure.dart';
import '../../domain/loans.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/ledger.dart';
import 'vbank_theme.dart';

/// A group's loans with request and detail flows.
final class MobileLoansScreen extends ConsumerWidget {
  /// The group lending.
  final String groupId;

  /// Creates the loans screen.
  const MobileLoansScreen({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Loans'),
          trailing: [
            IconButton.ghost(
              key: const ValueKey('request-loan-button'),
              icon: const Icon(LucideIcons.plus),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MobileRequestLoanScreen(groupId: groupId),
                ),
              ),
            ),
          ],
        ),
      ],
      child: MobileLoanList(groupId: groupId),
    );
  }
}

/// A group's loan rows, shared by the loans screen and the detail Loans
/// tab. Rows open the loan detail; requesting stays with the hosts.
final class MobileLoanList extends ConsumerWidget {
  /// The group lending.
  final String groupId;

  /// Creates the list.
  const MobileLoanList({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LoanRequest>> loans = ref.watch(
      loanListProvider(groupId),
    );
    return loans.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Center(child: Text('Error: $error')),
      data: (List<LoanRequest> list) {
        if (list.isEmpty) {
          return const Center(child: Text('No loans yet'));
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (BuildContext context, int i) {
            final LoanRequest loan = list[i];
            return _LoanRow(groupId: groupId, loan: loan);
          },
        );
      },
    );
  }
}

/// One loan row: amount and status plus where repayment stands, so the
/// list answers "how far along" without opening each loan.
final class _LoanRow extends ConsumerWidget {
  /// The group lending.
  final String groupId;

  /// The loan shown.
  final LoanRequest loan;

  /// Creates the row.
  const _LoanRow({required this.groupId, required this.loan});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<RepaymentSchedule>> schedule = ref.watch(
      scheduleProvider(loan.id),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => Navigator.push(
        context,
        VBankTheme.pageRoute<void>(
          context,
          MobileLoanDetailScreen(groupId: groupId, loanId: loan.id),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${loan.requestedAmount} · ${loan.status.name}').medium,
                  Text(
                    schedule.when(
                      loading: () => loan.status.name,
                      error: (_, _) => loan.status.name,
                      data: (List<RepaymentSchedule> list) =>
                          _progress(loan, list),
                    ),
                  ).small.muted,
                ],
              ),
            ),
            const Icon(LucideIcons.chevronRight, size: 16),
          ],
        ),
      ),
    );
  }

  /// Repayment standing in one line: repaid-of-expected plus overdue.
  static String _progress(LoanRequest loan, List<RepaymentSchedule> list) {
    if (list.isEmpty) {
      return loan.status == LoanStatus.pending
          ? 'Awaiting admin review'
          : loan.status.name;
    }
    var expected = 0.0;
    var paid = 0.0;
    var overdue = 0;
    for (final RepaymentSchedule s in list) {
      expected += s.expectedAmount;
      paid += s.paidAmount;
      if (s.isOverdue || s.status == RepaymentStatus.overdue) {
        overdue++;
      }
    }
    final String base =
        'Repaid ${paid.toStringAsFixed(2)} of ${expected.toStringAsFixed(2)}';
    return overdue == 0 ? base : '$base · $overdue overdue';
  }
}

/// Requests a loan as the signed-in member.
final class MobileRequestLoanScreen extends ConsumerStatefulWidget {
  /// The group lending.
  final String groupId;

  /// Creates the request screen.
  const MobileRequestLoanScreen({super.key, required this.groupId});

  @override
  ConsumerState<MobileRequestLoanScreen> createState() =>
      _MobileRequestLoanState();
}

final class _MobileRequestLoanState
    extends ConsumerState<MobileRequestLoanScreen> {
  /// Amount input.
  final TextEditingController _amount = TextEditingController();

  /// Term input (weeks).
  final TextEditingController _term = TextEditingController(text: '4');

  /// Reason input.
  final TextEditingController _reason = TextEditingController();

  /// Last failure, shown inline.
  String? _error;

  /// Save in flight.
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _term.dispose();
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    headers: [
      AppBar(
        leading: [
          IconButton.ghost(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        title: const Text('Request loan'),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Amount').small.semiBold.muted,
        const Gap(8),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          placeholder: const Text('0.00'),
        ),
        const Gap(16),
        Text('Term (weeks)').small.semiBold.muted,
        const Gap(8),
        TextField(
          controller: _term,
          keyboardType: TextInputType.number,
          placeholder: const Text('4'),
        ),
        const Gap(16),
        Text('Reason (optional)').small.semiBold.muted,
        const Gap(8),
        TextField(
          controller: _reason,
          placeholder: const Text('Why the money is needed'),
        ),
        const Gap(20),
        if (_error != null) ...[Text(_error!).small, const Gap(12)],
        PrimaryButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Sending…' : 'Send request'),
        ),
      ],
    ),
  );

  /// Validates locally, requests through the service, closes on success.
  Future<void> _save() async {
    final double? amount = double.tryParse(_amount.text.trim());
    final int? term = int.tryParse(_term.text.trim());
    final String? borrower = ref.read(authProvider).identity?.peerId;
    if (borrower == null) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    if (term == null || term <= 0) {
      setState(() => _error = 'Enter a term of at least 1 week.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(appServicesProvider)
        .loans
        .requestLoan(
          groupId: widget.groupId,
          borrowerPeerId: borrower,
          requestedAmount: amount,
          termWeeks: term,
          reason: _reason.text.trim().isEmpty ? null : _reason.text.trim(),
        );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _saving = false;
        _error = _explain(result.failure);
      });
      return;
    }
    Navigator.pop(context);
  }

  /// Machine failure codes to human words.
  static String _explain(Failure failure) => switch (failure) {
    PermissionFailure(:final action) => 'Not allowed ($action).',
    ValidationFailure(:final reason) => 'Check the form ($reason).',
    NotFoundFailure(:final subject) => 'Missing $subject.',
    ConflictFailure(:final subject) => 'Conflict on $subject.',
    NetworkFailure() => 'No connection.',
    IntegrityFailure(:final subject) => 'Rejected $subject.',
    StorageFailure() => 'Storage failed.',
  };
}

/// One loan: amounts, schedule and lifecycle actions.
final class MobileLoanDetailScreen extends ConsumerStatefulWidget {
  /// The group lending.
  final String groupId;

  /// The loan id.
  final String loanId;

  /// Creates the detail screen.
  const MobileLoanDetailScreen({
    super.key,
    required this.groupId,
    required this.loanId,
  });

  @override
  ConsumerState<MobileLoanDetailScreen> createState() =>
      _MobileLoanDetailState();
}

final class _MobileLoanDetailState
    extends ConsumerState<MobileLoanDetailScreen> {
  /// Repayment amount input.
  final TextEditingController _repay = TextEditingController();

  /// Last failure, shown inline.
  String? _error;

  @override
  void dispose() {
    _repay.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<LoanRequest>> loans = ref.watch(
      loanListProvider(widget.groupId),
    );
    final LoanRequest? loan = loans.valueOrNull
        ?.where((LoanRequest l) => l.id == widget.loanId)
        .firstOrNull;
    if (loan == null) {
      return Scaffold(
        headers: [
          AppBar(
            leading: [
              IconButton.ghost(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.pop(context),
              ),
            ],
            title: const Text('Loan'),
          ),
        ],
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    final String? me = ref.watch(authProvider).identity?.peerId;
    final AsyncValue<List<RepaymentSchedule>> schedule = ref.watch(
      scheduleProvider(loan.id),
    );
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: Text('${loan.requestedAmount}'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(loan.status.name).small.semiBold.muted,
          const Gap(8),
          Text('Due ${loan.totalWithInterest.toStringAsFixed(2)}').large,
          const Gap(16),
          if (_error != null) ...[Text(_error!).small, const Gap(12)],
          if (loan.isPending && me != null && me != loan.borrowerPeerId) ...[
            PrimaryButton(
              key: const ValueKey('approve-button'),
              onPressed: () => _decide(context, loan, me, true),
              child: const Text('Approve at requested'),
            ),
            const Gap(8),
            OutlineButton(
              onPressed: () => _decide(context, loan, me, false),
              child: const Text('Reject'),
            ),
            const Gap(8),
          ],
          if (loan.status == LoanStatus.approved) ...[
            PrimaryButton(
              key: const ValueKey('disburse-button'),
              onPressed: () => _disburse(context, loan, me!),
              child: const Text('Record disbursement'),
            ),
            const Gap(8),
          ],
          if (loan.isActive) ...[
            TextField(
              controller: _repay,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              placeholder: const Text('Repayment amount'),
            ),
            const Gap(8),
            PrimaryButton(
              key: const ValueKey('repay-button'),
              onPressed: () => _repayLoan(context, loan, me!),
              child: const Text('Record repayment'),
            ),
            const Gap(16),
          ],
          Text('Schedule').small.semiBold.muted,
          const Gap(8),
          schedule.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (Object error, _) => Text('Error: $error'),
            data: (List<RepaymentSchedule> list) => Column(
              children: [
                for (final RepaymentSchedule s in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '#${s.installmentNumber} · ${s.expectedAmount}',
                          ),
                        ),
                        Text(s.status.name).xSmall.muted,
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Approves or rejects through the service.
  Future<void> _decide(
    BuildContext context,
    LoanRequest loan,
    String me,
    bool approve,
  ) async {
    final services = ref.read(appServicesProvider).loans;
    final result = approve
        ? await services.approveLoan(
            loanId: loan.id,
            approvedAmount: loan.requestedAmount,
            approverPeerId: me,
          )
        : await services.rejectLoan(loanId: loan.id, approverPeerId: me);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = 'Failed (${result.failure}).');
    }
  }

  /// Disburses through the service.
  Future<void> _disburse(
    BuildContext context,
    LoanRequest loan,
    String me,
  ) async {
    final result = await ref
        .read(appServicesProvider)
        .loans
        .disburseLoan(loanId: loan.id, adminPeerId: me);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = 'Failed (${result.failure}).');
    }
  }

  /// Records a repayment through the service.
  Future<void> _repayLoan(
    BuildContext context,
    LoanRequest loan,
    String me,
  ) async {
    final double? amount = double.tryParse(_repay.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    final result = await ref
        .read(appServicesProvider)
        .loans
        .recordRepayment(loanId: loan.id, adminPeerId: me, amount: amount);
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = 'Failed (${result.failure}).');
    } else {
      _repay.clear();
    }
  }
}
