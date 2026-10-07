import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/identity.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// Creates a group in Fluent dress: name, contribution and rhythm.
/// On success selects the group and pops — the home shows its detail.
final class WindowsCreateGroupPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const WindowsCreateGroupPage({super.key});

  @override
  ConsumerState<WindowsCreateGroupPage> createState() =>
      _WindowsCreateGroupPageState();
}

final class _WindowsCreateGroupPageState
    extends ConsumerState<WindowsCreateGroupPage> {
  final TextEditingController _name = TextEditingController();
  final TextEditingController _amount = TextEditingController();
  ContributionFrequency _frequency = ContributionFrequency.weekly;
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _amount.dispose();
    super.dispose();
  }

  /// Validates locally, creates through the service, opens the detail.
  Future<void> _save() async {
    final UserIdentity? identity = ref.read(authProvider).identity;
    final double? amount = double.tryParse(_amount.text.trim());
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Give the group a name.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter a contribution above zero.');
      return;
    }
    if (identity == null) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(appServicesProvider)
        .groups
        .createGroup(
          name: _name.text,
          config: GroupConfig(
            groupId: 'new',
            contributionAmount: amount,
            frequency: _frequency,
          ),
          ownerPeerId: identity.peerId,
          ownerName: identity.displayName,
          ownerPublicKey: identity.publicKey,
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
    ref.read(selectedGroupIdProvider.notifier).state = result.value.id;
    if (mounted) {
      Navigator.pop(context);
    }
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

  @override
  Widget build(BuildContext context) => NavigationView(
    content: ScaffoldPage(
      header: PageHeader(
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('New group'),
      ),
      content: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          const Text('Name'),
          const SizedBox(height: 6),
          TextBox(
            controller: _name,
            placeholder: 'Village savings',
          ),
          const SizedBox(height: 12),
          const Text('Contribution'),
          const SizedBox(height: 6),
          TextBox(
            controller: _amount,
            placeholder: '100.00',
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
          ),
          const SizedBox(height: 12),
          const Text('Rhythm'),
          const SizedBox(height: 6),
          ComboBox<ContributionFrequency>(
            value: _frequency,
            items: [
              for (final ContributionFrequency frequency
                  in ContributionFrequency.values)
                ComboBoxItem(
                  value: frequency,
                  child: Text(frequency.name),
                ),
            ],
            onChanged: (ContributionFrequency? frequency) {
              if (frequency != null) {
                setState(() => _frequency = frequency);
              }
            },
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(_error!),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Creating…' : 'Create group'),
          ),
        ],
      ),
    ),
  );
}
