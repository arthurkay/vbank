import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../domain/core/failure.dart';
import '../../domain/loans.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/ledger.dart';

/// A group's loans with request and detail flows on macOS.
final class MacosLoansPage extends ConsumerWidget {
  /// The group lending.
  final String groupId;

  /// Creates the loans page.
  const MacosLoansPage({super.key, required this.groupId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<LoanRequest>> loans =
        ref.watch(loanListProvider(groupId));
    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Loans'),
        actions: [
          ToolBarIconButton(
            key: const ValueKey('request-loan-button'),
            label: 'Request loan',
            icon: const MacosIcon(CupertinoIcons.add),
            showLabel: false,
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => MacosRequestLoanPage(groupId: groupId),
              ),
            ),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              loans.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (Object error, _) => Center(child: Text('Error: $error')),
            data: (List<LoanRequest> list) {
              if (list.isEmpty) {
                return const Center(child: Text('No loans yet'));
              }
              return ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: list.length,
                itemBuilder: (BuildContext context, int i) {
                  final LoanRequest loan = list[i];
                  return MacosListTile(
                    leading:
                        const MacosIcon(CupertinoIcons.building_2_fill),
                    title: Text(
                      '${loan.requestedAmount} · ${loan.status.name}',
                      style: MacosTheme.of(context).typography.headline,
                    ),
                    onClick: () => Navigator.push(
                      context,
                      CupertinoPageRoute<void>(
                        builder: (_) => MacosLoanDetailPage(
                          groupId: groupId,
                          loanId: loan.id,
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Requests a loan as the signed-in member.
final class MacosRequestLoanPage extends ConsumerStatefulWidget {
  /// The group lending.
  final String groupId;

  /// Creates the request page.
  const MacosRequestLoanPage({super.key, required this.groupId});

  @override
  ConsumerState<MacosRequestLoanPage> createState() =>
      _MacosRequestLoanState();
}

final class _MacosRequestLoanState
    extends ConsumerState<MacosRequestLoanPage> {
  /// Amount input.
  final TextEditingController _amount = TextEditingController();

  /// Term input.
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
  Widget build(BuildContext context) => MacosScaffold(
        toolBar: ToolBar(
          leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
          title: const Text('Request loan'),
        ),
        children: [
          ContentArea(
            builder: (BuildContext context, ScrollController controller) =>
                ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                const Text('Amount'),
                MacosTextField(
                  controller: _amount,
                  placeholder: '0.00',
                ),
                const SizedBox(height: 12),
                const Text('Term (weeks)'),
                MacosTextField(
                  controller: _term,
                  placeholder: '4',
                ),
                const SizedBox(height: 12),
                const Text('Reason (optional)'),
                MacosTextField(
                  controller: _reason,
                  placeholder: 'Why the money is needed',
                ),
                const SizedBox(height: 20),
                if (_error != null) ...[
                  Text(_error!),
                  const SizedBox(height: 12),
                ],
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Sending…' : 'Send request'),
                ),
              ],
            ),
          ),
        ],
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
    final result =
        await ref.read(appServicesProvider).loans.requestLoan(
              groupId: widget.groupId,
              borrowerPeerId: borrower,
              requestedAmount: amount,
              termWeeks: term,
              reason: _reason.text.trim().isEmpty
                  ? null
                  : _reason.text.trim(),
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
final class MacosLoanDetailPage extends ConsumerStatefulWidget {
  /// The group lending.
  final String groupId;

  /// The loan id.
  final String loanId;

  /// Creates the detail page.
  const MacosLoanDetailPage({
    super.key,
    required this.groupId,
    required this.loanId,
  });

  @override
  ConsumerState<MacosLoanDetailPage> createState() =>
      _MacosLoanDetailState();
}

final class _MacosLoanDetailState
    extends ConsumerState<MacosLoanDetailPage> {
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
    final List<LoanRequest> loans =
        ref.watch(loanListProvider(widget.groupId)).valueOrNull ?? [];
    LoanRequest? loan;
    for (final LoanRequest l in loans) {
      if (l.id == widget.loanId) {
        loan = l;
      }
    }
    if (loan == null) {
      return MacosScaffold(
        toolBar: ToolBar(
          leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
          title: const Text('Loan'),
        ),
        children: const [
          ContentArea(builder: _loading),
        ],
      );
    }
    final LoanRequest current = loan;
    final String? me = ref.watch(authProvider).identity?.peerId;
    final AsyncValue<List<RepaymentSchedule>> schedule =
        ref.watch(scheduleProvider(loan.id));
    return MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(onPressed: () => Navigator.pop(context)),
        title: Text('${current.requestedAmount}'),
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              Text(
                current.status.name,
                style: MacosTheme.of(context).typography.title1,
              ),
              Text(
                'Due ${current.totalWithInterest.toStringAsFixed(2)}',
              ),
              const SizedBox(height: 16),
              if (_error != null) ...[
                Text(_error!),
                const SizedBox(height: 12),
              ],
              if (current.isPending &&
                  me != null &&
                  me != current.borrowerPeerId) ...[
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: () => _decide(current, me, true),
                  child: const Text('Approve at requested'),
                ),
                const SizedBox(height: 8),
                PushButton(
                  controlSize: ControlSize.large,
                  secondary: true,
                  onPressed: () => _decide(current, me, false),
                  child: const Text('Reject'),
                ),
                const SizedBox(height: 8),
              ],
              if (current.status == LoanStatus.approved) ...[
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: () => _disburse(current, me!),
                  child: const Text('Record disbursement'),
                ),
                const SizedBox(height: 8),
              ],
              if (current.isActive) ...[
                MacosTextField(
                  controller: _repay,
                  placeholder: 'Repayment amount',
                ),
                const SizedBox(height: 8),
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: () => _repayLoan(current, me!),
                  child: const Text('Record repayment'),
                ),
                const SizedBox(height: 16),
              ],
              const Text('Schedule'),
              schedule.when(
                loading: () => const Center(child: ProgressCircle()),
                error: (Object error, _) => Text('Error: $error'),
                data: (List<RepaymentSchedule> list) => Column(
                  children: [
                    for (final RepaymentSchedule s in list)
                      MacosListTile(
                        title: Text(
                          '#${s.installmentNumber} · ${s.expectedAmount}',
                        ),
                        subtitle: Text(s.status.name),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  static Widget _loading(BuildContext context, ScrollController _) =>
      const Center(child: ProgressCircle());

  /// Approves or rejects through the service.
  Future<void> _decide(LoanRequest loan, String me, bool approve) async {
    final services = ref.read(appServicesProvider).loans;
    final result = approve
        ? await services.approveLoan(
            loanId: loan.id,
            approvedAmount: loan.requestedAmount,
            approverPeerId: me,
          )
        : await services.rejectLoan(
            loanId: loan.id,
            approverPeerId: me,
          );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = 'Failed (${result.failure}).');
    }
  }

  /// Disburses through the service.
  Future<void> _disburse(LoanRequest loan, String me) async {
    final result =
        await ref.read(appServicesProvider).loans.disburseLoan(
              loanId: loan.id,
              adminPeerId: me,
            );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() => _error = 'Failed (${result.failure}).');
    }
  }

  /// Records a repayment through the service.
  Future<void> _repayLoan(LoanRequest loan, String me) async {
    final double? amount = double.tryParse(_repay.text.trim());
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    final result =
        await ref.read(appServicesProvider).loans.recordRepayment(
              loanId: loan.id,
              adminPeerId: me,
              amount: amount,
            );
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
