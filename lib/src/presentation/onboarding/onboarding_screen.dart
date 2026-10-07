import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'onboarding_action.dart';

/// First-run screen in shadcn dress (mobile): the name groups know this
/// person by. Saves through [saveOnboardingIdentity] and pops on success,
/// which flips the home from onboarding to the group list.
final class OnboardingScreen extends ConsumerStatefulWidget {
  /// This device's peer id, or null while the node is down.
  final String? Function() peerIdOf;

  /// This device's Ed25519 public key bytes.
  final Uint8List publicKey;

  /// Creates the onboarding screen.
  const OnboardingScreen({
    super.key,
    required this.peerIdOf,
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

  /// Saves through the shared action; pops when the home should rebuild.
  Future<void> save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    final OnboardingSaveResult result = await saveOnboardingIdentity(
      ref,
      peerIdOf: widget.peerIdOf,
      publicKey: widget.publicKey,
      displayName: _name.text,
    );
    if (!mounted) {
      return;
    }
    if (result != OnboardingSaveResult.saved) {
      setState(() {
        _saving = false;
        _error = onboardingErrorText(result);
      });
      return;
    }
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
