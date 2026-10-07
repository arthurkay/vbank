import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../onboarding/onboarding_action.dart';

/// First-run page in Yaru dress: the name groups know this person by.
/// Same [saveOnboardingIdentity] contract as the mobile screen.
final class LinuxOnboardingPage extends ConsumerStatefulWidget {
  /// This device's peer id, or null while the node is down.
  final String? Function() peerIdOf;

  /// This device's Ed25519 public key bytes.
  final Uint8List publicKey;

  /// Creates the onboarding page.
  const LinuxOnboardingPage({
    super.key,
    required this.peerIdOf,
    required this.publicKey,
  });

  @override
  ConsumerState<LinuxOnboardingPage> createState() =>
      _LinuxOnboardingPageState();
}

final class _LinuxOnboardingPageState
    extends ConsumerState<LinuxOnboardingPage> {
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
    body: Center(
      child: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'vBank',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            const Text('Village banking that works offline.'),
            const SizedBox(height: 20),
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'Your name'),
              onSubmitted: (_) => save(),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : save,
              child: Text(_saving ? 'Saving…' : 'Get started'),
            ),
          ],
        ),
      ),
    ),
  );
}
