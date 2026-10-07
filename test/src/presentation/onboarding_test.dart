import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/onboarding/onboarding_screen.dart';

import 'pump.dart';

void main() {
  group('onboarding', () {
    testWidgets('saves the identity and pops', (tester) async {
      final PresentationWorld world = PresentationWorld();
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: OnboardingScreen(
              peerIdOf: () => 'owner',
              publicKey: Uint8List.fromList(List.filled(32, 7)),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'Amina');
      await tester.tap(find.text('Get started'));
      await settle(tester);

      final loaded = await world.backupRepo.loadIdentity();
      expect(loaded.isOk, isTrue);
      expect(loaded.value?.displayName, 'Amina');
      expect(loaded.value?.peerId, 'owner');
      // Saved and popped: the form is gone.
      expect(find.text('Get started'), findsNothing);
    });

    testWidgets('empty name shows an error', (tester) async {
      final PresentationWorld world = PresentationWorld();
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: OnboardingScreen(
              peerIdOf: () => 'owner',
              publicKey: Uint8List.fromList(List.filled(32, 7)),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Get started'));
      await settle(tester);

      expect(find.textContaining('name your group'), findsOneWidget);
      final loaded = await world.backupRepo.loadIdentity();
      expect(loaded.value, isNull);
    });

    testWidgets('node down shows a retry instead of silence', (tester) async {
      final PresentationWorld world = PresentationWorld();
      String? peerId;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: OnboardingScreen(
              peerIdOf: () => peerId,
              publicKey: Uint8List.fromList(List.filled(32, 7)),
            ),
          ),
        ),
      );
      await settle(tester);

      await tester.enterText(find.byType(TextField), 'Amina');
      await tester.tap(find.text('Get started'));
      await settle(tester);

      // The node is down: an error, nothing saved — and no silent exit.
      expect(find.textContaining("isn't running"), findsOneWidget);
      expect(
        (await world.backupRepo.loadIdentity()).value,
        isNull,
      );

      // The node comes up; the same tap retries and succeeds.
      peerId = 'owner';
      await tester.tap(find.text('Get started'));
      await settle(tester);

      expect(
        (await world.backupRepo.loadIdentity()).value?.displayName,
        'Amina',
      );
      expect(find.text('Get started'), findsNothing);
    });
  });
}
