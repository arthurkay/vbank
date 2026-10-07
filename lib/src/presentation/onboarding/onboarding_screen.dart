import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/identity.dart';
import '../app_scope.dart';
import '../providers/auth.dart';

/// First-run screen: the name groups know this person by.
///
/// Saves the identity row (keyed by [peerId]) and refreshes auth on
/// success, which flips the home from onboarding to the group list.
/// Widget tests pass a fake peer id and key.
final class OnboardingScreen extends ConsumerStatefulWidget {
  /// This device's peer id (the node's, once it has started).
  final String peerId;

  /// This device's Ed25519 public key bytes.
  final Uint8List publicKey;

  /// Creates the onboarding screen.
  const OnboardingScreen({
    super.key,
    required this.peerId,
    required this.publicKey,
  });

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

final class _OnboardingScreenState
    extends ConsumerState<OnboardingScreen> {
  final TextEditingController _name = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  /// Saves the identity and returns to the home, which rebuilds signed in.
  Future<void> save() async {
    if (_name.text.trim().isEmpty) {
      setState(() => _error = 'Enter the name your group knows you by.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result = await ref
        .read(appRepositoriesProvider)
        .backups
        .saveIdentity(
          UserIdentity(
            peerId: widget.peerId,
            displayName: _name.text.trim(),
            publicKey: widget.publicKey,
            createdAt: DateTime.now().toUtc(),
          ),
        );
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
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('vBank').xLarge.bold,
                const Gap(8),
                const Text('Village banking that works offline.'),
                const Gap(20),
                TextField(
                  controller: _name,
                  placeholder: const Text('Your name'),
                  onSubmitted: (_) => save(),
                ),
                if (_error != null) ...[
                  const Gap(8),
                  Text(_error!).muted,
                ],
                const Gap(16),
                PrimaryButton(
                  onPressed: _saving ? null : save,
                  child: Text(_saving ? 'Saving…' : 'Get started'),
                ),
              ],
            ),
          ),
        ),
      );
}
