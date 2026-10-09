import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/identity.dart';
import '../app_scope.dart';
import '../providers/auth.dart';

/// This device's identity in Fluent dress: peer id with copy, display
/// name edit and sign out.
final class WindowsIdentityPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const WindowsIdentityPage({super.key});

  @override
  ConsumerState<WindowsIdentityPage> createState() =>
      _WindowsIdentityPageState();
}

final class _WindowsIdentityPageState
    extends ConsumerState<WindowsIdentityPage> {
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
    final result =
        await ref.read(appRepositoriesProvider).backups.clearIdentity();
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
    return NavigationView(
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Identity'),
        ),
        content: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            if (identity == null)
              const Text('Not signed in.')
            else ...[
              const Text('Peer ID'),
              const SizedBox(height: 6),
              SelectableText(identity.peerId),
              const SizedBox(height: 8),
              Button(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: identity.peerId),
                  );
                },
                child: const Text('Copy peer ID'),
              ),
              const SizedBox(height: 16),
              const Text('Display name'),
              const SizedBox(height: 6),
              TextBox(
                controller: _name,
                placeholder: 'Your name',
              ),
              const SizedBox(height: 8),
              FilledButton(
                onPressed: _saving ? null : () => _saveName(identity),
                child: Text(_saving ? 'Saving…' : 'Save name'),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _signOut,
                child: Text(
                  _confirmSignOut ? 'Confirm sign out' : 'Sign out',
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
