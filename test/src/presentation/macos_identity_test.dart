import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/identity_page.dart';
import 'package:vbank/src/presentation/providers/auth.dart';

import 'pump.dart';

void main() {
  group('macos identity', () {
    testWidgets('shows peer id and renames', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final PresentationWorld world = PresentationWorld();
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: const MacosApp(home: MacosIdentityPage()),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MacosIdentityPage)),
      );
      await world.signIn(container);
      await settle(tester);

      expect(find.text('owner'), findsWidgets);
      await tester.enterText(find.byType(MacosTextField), 'Amina Nzila');
      await tester.tap(find.text('Save name'));
      await settle(tester);

      final identity = await world.backupRepo.loadIdentity();
      expect(identity.value?.displayName, 'Amina Nzila');
      expect(container.read(authProvider).identity?.displayName, 'Amina Nzila');
    });

    testWidgets('sign out clears identity', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final PresentationWorld world = PresentationWorld();
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: const MacosApp(home: MacosIdentityPage()),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MacosIdentityPage)),
      );
      await world.signIn(container);
      await settle(tester);

      await tester.tap(find.text('Sign out'));
      await settle(tester);
      await tester.tap(find.text('Confirm sign out'));
      await settle(tester);

      final cleared = await world.backupRepo.loadIdentity();
      expect(cleared.value, isNull);
      expect(container.read(authProvider).identity, isNull);
      expect(find.text('Peer ID'), findsNothing);
    });
  });
}
