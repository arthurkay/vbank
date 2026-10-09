import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/identity.dart';
import '../app_scope.dart';
import '../providers/auth.dart';

/// This device's identity in shadcn dress: peer id with copy, display
/// name edit and sign out. Two-tap confirm guards the sign-out.
final class MobileIdentityScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MobileIdentityScreen({super.key});

  @override
  ConsumerState<MobileIdentityScreen> createState() =>
      _MobileIdentityScreenState();
}

final class _MobileIdentityScreenState
    extends ConsumerState<MobileIdentityScreen> {
  final TextEditingController _name = TextEditingController();
  String? _error;
  bool _saving = false;
  bool _confirmSignOut = false;
  bool _nameSet = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Saves the edited display name.
  Future<void> _saveName(UserIdentity identity) async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter a name.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(appRepositoriesProvider)
        .backups
        .saveIdentity(identity.copyWith(displayName: _name.text.trim()));
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _saving = false;
        _error = 'Could not save — try again.';
      });
      return;
    }
    await ref.read(authProvider.notifier).refresh();
    if (mounted) {
      setState(() => _saving = false);
    }
  }

  /// Clears the identity, returning to onboarding.
  Future<void> _signOut() async {
    if (!_confirmSignOut) {
      setState(() {
        _confirmSignOut = true;
        _error = null;
      });
      return;
    }
    final result = await ref
        .read(appRepositoriesProvider)
        .backups
        .clearIdentity();
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _confirmSignOut = false;
        _error = 'Could not sign out — try again.';
      });
      return;
    }
    await ref.read(authProvider.notifier).refresh();
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final AuthState auth = ref.watch(authProvider);
    final UserIdentity? identity = auth.identity;
    if (identity != null && !_nameSet) {
      _name.text = identity.displayName;
      _nameSet = true;
    }
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Identity'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (identity == null)
            const Text('Not signed in.').small.muted
          else ...[
            Text('Peer ID').small.semiBold.muted,
            const Gap(8),
            SelectableText(identity.peerId).small,
            const Gap(8),
            OutlineButton(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: identity.peerId));
              },
              child: const Text('Copy peer ID'),
            ),
            const Gap(16),
            Text('Display name').small.semiBold.muted,
            const Gap(8),
            TextField(
              controller: _name,
              placeholder: const Text('Your name'),
              onSubmitted: (_) => _saveName(identity),
            ),
            const Gap(8),
            PrimaryButton(
              onPressed: _saving ? null : () => _saveName(identity),
              child: Text(_saving ? 'Saving…' : 'Save name'),
            ),
            const Gap(20),
            PrimaryButton(
              onPressed: _signOut,
              child: Text(_confirmSignOut ? 'Confirm sign out' : 'Sign out'),
            ),
            if (_error != null) ...[const Gap(12), Text(_error!).small],
          ],
        ],
      ),
    );
  }
}
