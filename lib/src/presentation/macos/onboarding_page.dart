import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../onboarding/onboarding_action.dart';

/// First-run page in Macos dress: the name groups know this person by.
/// Same [saveOnboardingIdentity] contract as the mobile screen.
final class MacosOnboardingPage extends ConsumerStatefulWidget {
  /// This device's peer id, or null while the node is down.
  final String? Function() peerIdOf;

  /// This device's Ed25519 public key bytes.
  final Uint8List publicKey;

  /// Creates the onboarding page.
  const MacosOnboardingPage({
    super.key,
    required this.peerIdOf,
    required this.publicKey,
  });

  @override
  ConsumerState<MacosOnboardingPage> createState() =>
      _MacosOnboardingPageState();
}

final class _MacosOnboardingPageState
    extends ConsumerState<MacosOnboardingPage> {
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
  Widget build(BuildContext context) => MacosWindow(
    child: MacosScaffold(
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController _) => Center(
            child: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'vBank',
                    style: MacosTheme.of(context).typography.largeTitle,
                  ),
                  const SizedBox(height: 8),
                  const Text('Village banking that works offline.'),
                  const SizedBox(height: 20),
                  MacosTextField(
                    controller: _name,
                    placeholder: 'Your name',
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 8),
                    Text(_error!),
                  ],
                  const SizedBox(height: 16),
                  PushButton(
                    controlSize: ControlSize.large,
                    onPressed: _saving ? null : save,
                    child: Text(_saving ? 'Saving…' : 'Get started'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
