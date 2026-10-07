import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/identity.dart';
import '../app_scope.dart';
import '../providers/auth.dart';

/// How an onboarding save went. Screens map these to their own words.
enum OnboardingSaveResult {
  /// The identity row is saved and auth refreshed: pop to the home.
  saved,

  /// The name was blank.
  emptyName,

  /// The node is down, so there is no peer id yet. Retry later.
  nodeDown,

  /// The row would not save.
  failed,
}

/// Saves the first-run identity: the name groups know this person by,
/// keyed by the node's peer id (read fresh — the node may have started
/// after the screen opened). Refreshes auth on success.
Future<OnboardingSaveResult> saveOnboardingIdentity(
  WidgetRef ref, {
  required String? Function() peerIdOf,
  required Uint8List publicKey,
  required String displayName,
}) async {
  final String? peerId = peerIdOf();
  if (peerId == null) {
    return OnboardingSaveResult.nodeDown;
  }
  if (displayName.trim().isEmpty) {
    return OnboardingSaveResult.emptyName;
  }
  final result = await ref
      .read(appRepositoriesProvider)
      .backups
      .saveIdentity(
        UserIdentity(
          peerId: peerId,
          displayName: displayName.trim(),
          publicKey: publicKey,
          createdAt: DateTime.now().toUtc(),
        ),
      );
  if (result.isErr) {
    return OnboardingSaveResult.failed;
  }
  await ref.read(authProvider.notifier).refresh();
  return OnboardingSaveResult.saved;
}

/// Words for [OnboardingSaveResult] failures; null when [result] is saved.
String? onboardingErrorText(OnboardingSaveResult result) => switch (result) {
  OnboardingSaveResult.saved => null,
  OnboardingSaveResult.emptyName =>
    'Enter the name your group knows you by.',
  OnboardingSaveResult.nodeDown =>
    "The sync node isn't running yet — Retry once it is.",
  OnboardingSaveResult.failed => 'Could not save — try again.',
};
