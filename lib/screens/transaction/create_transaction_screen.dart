import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../ui/ui.dart';

/// Owner/admin records money movements (DESIGN_PLAN §13: members are
/// read-only). Contributions are *for* a chosen member; the admin signs.
class CreateTransactionScreen extends ConsumerStatefulWidget {
  const CreateTransactionScreen({super.key});

  @override
  ConsumerState<CreateTransactionScreen> createState() => _CreateTransactionScreenState();
}

class _CreateTransactionScreenState extends ConsumerState<CreateTransactionScreen> {
  static const _types = [TransactionType.contribution, TransactionType.penalty, TransactionType.withdrawal];
  TransactionType _type = TransactionType.contribution;
  String? _memberPeerId;
  final _amount = TextEditingController();
  final _note = TextEditingController();
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    final group = ref.read(selectedGroupProvider);
    _memberPeerId = ref.read(authProvider).identity?.peerId;
    if (group != null) _amount.text = group.config.contributionAmount.toStringAsFixed(2);
  }

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final amount = double.tryParse(_amount.text);
    if (amount == null || amount <= 0) return showMessage(context, 'Please enter a valid amount', error: true);
    final member = _memberPeerId;
    if (member == null) return showMessage(context, 'Please choose a member', error: true);

    setState(() => _isLoading = true);
    try {
      final group = ref.read(selectedGroupProvider);
      if (group == null) throw Exception('No group selected');
      final (from, to) = switch (_type) {
        TransactionType.withdrawal || TransactionType.loan => ('group', member),
        _ => (member, 'group'),
      };
      await ref.read(transactionListProvider(group.id).notifier).createTransaction(
            fromPeerId: from,
            toPeerId: to,
            type: _type,
            amount: amount,
            note: _note.text.isEmpty ? null : _note.text,
          );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Transaction recorded');
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
    final canWrite = ref.watch(canWriteProvider);
    final members = (group?.members ?? const <Member>[]).where((m) => m.status == MemberStatus.active).toList()
      ..sort((a, b) => a.name.compareTo(b.name));
    final selected = members.where((m) => m.peerId == _memberPeerId).firstOrNull;

    return AppPage(
      title: 'New Transaction',
      child: !canWrite
          ? const EmptyState(
              icon: LucideIcons.lock,
              title: 'Admins only',
              subtitle: 'Only the group owner or an admin can record transactions.',
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Segmented<TransactionType>(
                    values: _types,
                    selected: _type,
                    label: (t) => '${t.name[0].toUpperCase()}${t.name.substring(1)}',
                    onChanged: (t) => setState(() => _type = t),
                  ),
                  const Gap(6),
                  const Text('Loans and repayments are recorded from the loan itself.').xSmall.muted,
                  const Gap(20),
                  LabeledField(
                    label: 'Member',
                    child: SimpleSelect<Member>(
                      value: selected,
                      items: members,
                      label: (m) => m.name,
                      onChanged: (m) => setState(() => _memberPeerId = m?.peerId),
                      placeholder: 'Choose a member',
                    ),
                  ),
                  const Gap(20),
                  LabeledField(
                    label: 'Amount (${group?.config.currency ?? 'ZMW'})',
                    child: TextField(
                      controller: _amount,
                      autofocus: true,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    ),
                  ),
                  const Gap(20),
                  LabeledField(
                    label: 'Note (optional)',
                    child: TextField(controller: _note, maxLines: 2),
                  ),
                  const Gap(32),
                  Button.primary(
                    onPressed: _isLoading ? null : _create,
                    child: _isLoading ? const CircularProgressIndicator(size: 18) : const Text('Record Transaction'),
                  ),
                ],
              ),
            ),
    );
  }
}
