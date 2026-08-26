import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/group_provider.dart';
import '../../providers/loan_provider.dart';
import '../../ui/ui.dart';

class RequestLoanScreen extends ConsumerStatefulWidget {
  const RequestLoanScreen({super.key});

  @override
  ConsumerState<RequestLoanScreen> createState() => _RequestLoanScreenState();
}

class _RequestLoanScreenState extends ConsumerState<RequestLoanScreen> {
  final _amount = TextEditingController();
  final _term = TextEditingController(text: '4');
  final _reason = TextEditingController();
  bool _isLoading = false;
  List<String> _problems = const [];

  @override
  void dispose() {
    _amount.dispose();
    _term.dispose();
    _reason.dispose();
    super.dispose();
  }

  Future<void> _checkEligibility() async {
    final group = ref.read(selectedGroupProvider);
    final amount = double.tryParse(_amount.text);
    if (group == null || amount == null || amount <= 0) return;
    final problems = await ref.read(loanListProvider(group.id).notifier).eligibilityProblems(amount);
    if (mounted) setState(() => _problems = problems);
  }

  Future<void> _requestLoan() async {
    final amount = double.tryParse(_amount.text);
    final term = int.tryParse(_term.text);
    if (amount == null || amount <= 0 || term == null || term <= 0) {
      return showMessage(context, 'Please enter a valid amount and term', error: true);
    }
    setState(() => _isLoading = true);
    try {
      final group = ref.read(selectedGroupProvider);
      if (group == null) throw Exception('No group selected');
      final loan = await ref.read(loanListProvider(group.id).notifier).requestLoan(
            requestedAmount: amount,
            termWeeks: term,
            reason: _reason.text.isEmpty ? null : _reason.text,
          );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, loan.status.name == 'approved' ? 'Loan approved' : 'Loan request submitted');
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(selectedGroupProvider);
    final cfg = group?.config;
    return AppPage(
      title: 'Request Loan',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (cfg != null)
              Alert(
                leading: const Icon(LucideIcons.info),
                title: const Text('Group loan terms'),
                content: Text(
                  'Up to ${cfg.maxLoanMultiplier}× your contributions · ${(cfg.loanInterestRate * 100).toStringAsFixed(0)}% interest · '
                  'after ${cfg.minContributionsForLoan} contributions · ${cfg.requireLoanApproval ? 'needs admin approval' : 'auto-approved'}',
                ),
              ),
            const Gap(20),
            LabeledField(
              label: 'Loan amount (${cfg?.currency ?? 'ZMW'})',
              child: TextField(cursorOpacityAnimates: false, 
                controller: _amount,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                onChanged: (_) => _checkEligibility(),
              ),
            ),
            if (_problems.isNotEmpty) ...[
              const Gap(12),
              Alert.destructive(
                leading: const Icon(LucideIcons.triangleAlert),
                title: const Text('Not eligible yet'),
                content: Text(_problems.join('\n')),
              ),
            ],
            const Gap(20),
            LabeledField(
              label: 'Term (weeks)',
              child: TextField(cursorOpacityAnimates: false, controller: _term, keyboardType: TextInputType.number),
            ),
            const Gap(20),
            LabeledField(
              label: 'Reason (optional)',
              child: TextField(cursorOpacityAnimates: false, controller: _reason, maxLines: 3),
            ),
            const Gap(32),
            Button.primary(
              onPressed: _isLoading ? null : _requestLoan,
              child: _isLoading ? const CircularProgressIndicator(size: 18) : const Text('Submit Request'),
            ),
          ],
        ),
      ),
    );
  }
}
