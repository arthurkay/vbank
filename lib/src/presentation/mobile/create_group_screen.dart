import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/identity.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// Creates a group in shadcn dress: name, contribution and rhythm.
/// On success selects the group and pops — the home shows its detail.
final class MobileCreateGroupScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MobileCreateGroupScreen({super.key});

  @override
  ConsumerState<MobileCreateGroupScreen> createState() =>
      _MobileCreateGroupScreenState();
}

final class _MobileCreateGroupScreenState
    extends ConsumerState<MobileCreateGroupScreen> {
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
  Widget build(BuildContext context) => Scaffold(
    headers: [
      AppBar(
        leading: [
          IconButton.ghost(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        title: const Text('New group'),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Name').small.semiBold.muted,
        const Gap(8),
        TextField(
          controller: _name,
          placeholder: const Text('Village savings'),
          onSubmitted: (_) => _save(),
        ),
        const Gap(16),
        Text('Contribution').small.semiBold.muted,
        const Gap(8),
        TextField(
          controller: _amount,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          placeholder: const Text('100.00'),
        ),
        const Gap(16),
        Text('Rhythm').small.semiBold.muted,
        const Gap(8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final ContributionFrequency frequency
                in ContributionFrequency.values)
              frequency == _frequency
                  ? PrimaryButton(
                      onPressed: () =>
                          setState(() => _frequency = frequency),
                      child: Text(frequency.name),
                    )
                  : OutlineButton(
                      onPressed: () =>
                          setState(() => _frequency = frequency),
                      child: Text(frequency.name),
                    ),
          ],
        ),
        const Gap(20),
        if (_error != null) ...[
          Text(_error!).small,
          const Gap(12),
        ],
        PrimaryButton(
          onPressed: _saving ? null : _save,
          child: Text(_saving ? 'Creating…' : 'Create group'),
        ),
      ],
    ),
  );
}
