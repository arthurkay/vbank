import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/home_screen.dart';
import 'package:vbank/src/presentation/providers/auth.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('mobile identity', () {
    testWidgets('shows peer id and renames', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileHomeScreen(onCreateIdentity: createIdentity),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(MobileHomeScreen)),
      );
      await settle(tester);
      await tester.tap(find.text('Get started'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('identity-button')));
      await settle(tester);

      // Peer id shown, name pre-filled from identity.
      expect(find.text('owner'), findsWidgets);
      await tester.enterText(find.byType(TextField), 'Amina Nzila');
      await tester.tap(find.text('Save name'));
      await settle(tester);

      final identity = await world.backupRepo.loadIdentity();
      expect(identity.value?.displayName, 'Amina Nzila');
      expect(container.read(authProvider).identity?.displayName, 'Amina Nzila');
    });

    testWidgets('sign out returns to onboarding', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileHomeScreen(onCreateIdentity: createIdentity),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(MobileHomeScreen)),
      );
      await settle(tester);
      await tester.tap(find.text('Get started'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('identity-button')));
      await settle(tester);
      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await tester.tap(find.text('Confirm sign out'));
      await settle(tester);

      expect(find.text('Get started'), findsOneWidget);
      expect(container.read(selectedGroupIdProvider), isNull);
    });
  });
}
