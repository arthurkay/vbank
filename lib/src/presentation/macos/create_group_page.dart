import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/identity.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// Creates a group in Macos dress: name, contribution and rhythm.
/// On success selects the group and pops — the home shows its detail.
final class MacosCreateGroupPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const MacosCreateGroupPage({super.key});

  @override
  ConsumerState<MacosCreateGroupPage> createState() =>
      _MacosCreateGroupPageState();
}

final class _MacosCreateGroupPageState
    extends ConsumerState<MacosCreateGroupPage> {
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
  Widget build(BuildContext context) {
    return MacosWindow(
      child: MacosScaffold(
        toolBar: ToolBar(
          leading: MacosBackButton(
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('New group'),
        ),
        children: [
          ContentArea(
            builder: (BuildContext context, ScrollController controller) =>
                ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                const Text('Name'),
                MacosTextField(
                  controller: _name,
                  placeholder: 'Village savings',
                ),
                const SizedBox(height: 12),
                const Text('Contribution'),
                MacosTextField(
                  controller: _amount,
                  placeholder: '100.00',
                ),
                const SizedBox(height: 12),
                const Text('Rhythm'),
                MacosPopupButton<ContributionFrequency>(
                  value: _frequency,
                  items: [
                    for (final ContributionFrequency frequency
                        in ContributionFrequency.values)
                      MacosPopupMenuItem(
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
                PushButton(
                  controlSize: ControlSize.large,
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Creating…' : 'Create group'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
