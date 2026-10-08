import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../app/invite_link.dart';
import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// Joins a group from a share link in Macos dress: paste the link,
/// confirm the name, join. On success selects the group and pops — the
/// home shows its detail.
final class MacosJoinGroupPage extends ConsumerStatefulWidget {
  /// Joins with a link; pages never touch sync directly.
  final Future<Result<Unit>> Function({
    required String link,
    required String displayName,
  })
  onJoin;

  /// Creates the page.
  const MacosJoinGroupPage({super.key, required this.onJoin});

  @override
  ConsumerState<MacosJoinGroupPage> createState() =>
      _MacosJoinGroupPageState();
}

final class _MacosJoinGroupPageState
    extends ConsumerState<MacosJoinGroupPage> {
  final TextEditingController _link = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  /// Validates locally, joins as the signed-in identity through the
  /// callback, opens the detail.
  Future<void> _save() async {
    if (_link.text.trim().isEmpty) {
      setState(() => _error = 'Paste the invite link first.');
      return;
    }
    final String? displayName =
        ref.read(authProvider).identity?.displayName;
    if (displayName == null || displayName.trim().isEmpty) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final Result<Unit> result = await widget.onJoin(
      link: _link.text.trim(),
      displayName: displayName,
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
    final String? groupId =
        InviteLink.tryParse(_link.text.trim())?.groupId;
    if (groupId != null) {
      ref.read(selectedGroupIdProvider.notifier).state = groupId;
    }
    if (mounted) {
      Navigator.pop(context);
    }
  }

  /// Machine failure codes to human words.
  static String _explain(Failure failure) => switch (failure) {
    PermissionFailure(:final action) => 'Not allowed ($action).',
    ValidationFailure(:final reason) => switch (reason) {
      'inviteLinkMalformed' => 'That link is not a vBank invite.',
      'inviteExpired' => 'That invite expired — ask for a new link.',
      'syncNotSignedIn' => 'Restart the app and try again.',
      'identityNameEmpty' => 'Enter the name your group knows you by.',
      'noRelays' => 'No relay reachable — check connection and settings.',
      'snapshotUnreachable' =>
          'The inviter has not synced yet — ask them to open the app, '
          'then retry.',
      _ => 'Check the form ($reason).',
    },
    NotFoundFailure(:final subject) => 'Missing $subject.',
    ConflictFailure(:final subject) => 'Conflict on $subject.',
    NetworkFailure() => 'Could not reach the group — try again on sync.',
    IntegrityFailure(:final subject) => 'Rejected $subject.',
    StorageFailure() => 'Storage failed.',
  };

  @override
  Widget build(BuildContext context) => MacosWindow(
    child: MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Join group'),
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              const Text('Invite link'),
              MacosTextField(
                controller: _link,
                placeholder: 'vbank://join?…',
              ),
              const SizedBox(height: 20),
              if (_error != null) ...[
                Text(_error!),
                const SizedBox(height: 12),
              ],
              PushButton(
                key: const ValueKey('join-submit-button'),
                controlSize: ControlSize.large,
                onPressed: _saving ? null : _save,
                child: Text(_saving ? 'Joining…' : 'Join group'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
