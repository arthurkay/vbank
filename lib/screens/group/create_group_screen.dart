import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/group.dart';
import '../../providers/group_provider.dart';
import '../../services/group_key_service.dart';
import '../../ui/ui.dart';

class CreateGroupScreen extends ConsumerStatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  ConsumerState<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends ConsumerState<CreateGroupScreen> {
  final _name = TextEditingController();
  final _amount = TextEditingController();
  final _passphrase = TextEditingController();
  final _confirm = TextEditingController();
  ContributionFrequency _frequency = ContributionFrequency.weekly;
  bool _requireApproval = false;
  bool _isLoading = false;

  @override
  void dispose() {
    for (final c in [_name, _amount, _passphrase, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _name.text.trim();
    final amount = double.tryParse(_amount.text);
    if (name.isEmpty) return showMessage(context, 'Please enter a group name', error: true);
    if (amount == null || amount <= 0) return showMessage(context, 'Please enter a valid amount', error: true);
    final passphraseError = GroupKeyService.validatePassphrase(_passphrase.text);
    if (passphraseError != null) return showMessage(context, passphraseError, error: true);
    if (_passphrase.text.trim() != _confirm.text.trim()) {
      return showMessage(context, 'Passphrases do not match', error: true);
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(groupListProvider.notifier).createGroup(
            name: name,
            config: GroupConfig(groupId: '', contributionAmount: amount, frequency: _frequency),
            passphrase: _passphrase.text,
            requireApproval: _requireApproval,
          );
      if (mounted) {
        Navigator.pop(context);
        showMessage(context, 'Group created');
      }
    } catch (e) {
      if (mounted) showMessage(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppPage(
      title: 'Create Group',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            LabeledField(
              label: 'Group name',
              child: TextField(cursorOpacityAnimates: false, 
                controller: _name,
                placeholder: const Text('e.g. Village Savings Group'),
                textCapitalization: TextCapitalization.words,
              ),
            ),
            const Gap(20),
            LabeledField(
              label: 'Contribution amount (ZMW)',
              child: TextField(cursorOpacityAnimates: false, 
                controller: _amount,
                placeholder: const Text('e.g. 50'),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
              ),
            ),
            const Gap(20),
            LabeledField(
              label: 'Frequency',
              child: Segmented<ContributionFrequency>(
                values: ContributionFrequency.values,
                selected: _frequency,
                label: (f) => f.name,
                onChanged: (f) => setState(() => _frequency = f),
              ),
            ),
            const Gap(20),
            LabeledField(
              label: 'Group passphrase',
              helper: 'Shared secret that encrypts the group\'s records. Tell it to members in person — '
                  'anyone who knows it can join and read the group\'s data.',
              child: TextField(cursorOpacityAnimates: false, 
                controller: _passphrase,
                obscureText: true,
                placeholder: const Text('e.g. chilenje-savings-2026'),
                features: [InputFeature.passwordToggle()],
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
            const Gap(20),
            LabeledField(
              label: 'Confirm passphrase',
              child: TextField(cursorOpacityAnimates: false, 
                controller: _confirm,
                obscureText: true,
                features: [InputFeature.passwordToggle()],
                autocorrect: false,
                enableSuggestions: false,
              ),
            ),
            const Gap(20),
            Panel(
              child: Basic(
                title: const Text('New members need approval'),
                subtitle: const Text('Joiners wait until an admin approves them').small.muted,
                trailing: Switch(value: _requireApproval, onChanged: (v) => setState(() => _requireApproval = v)),
                trailingAlignment: Alignment.center,
              ),
            ),
            const Gap(32),
            Button.primary(
              onPressed: _isLoading ? null : _createGroup,
              child: _isLoading ? const CircularProgressIndicator(size: 18) : const Text('Create Group'),
            ),
          ],
        ),
      ),
    );
  }
}
