import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/linux/home_page.dart';
import 'package:vbank/src/presentation/providers/auth.dart';
import 'package:vbank/src/presentation/providers/groups.dart';
import 'package:yaru/yaru.dart';

import 'pump.dart';

void main() {
  group('linux identity', () {
    testWidgets('shows peer id and renames', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: YaruTheme(
            builder: (context, yaru, child) => MaterialApp(
              theme: yaru.theme,
              darkTheme: yaru.darkTheme,
              home: LinuxHomePage(onCreateIdentity: createIdentity),
            ),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxHomePage)),
      );
      await settle(tester);
      await tester.tap(find.text('Get started'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('identity-button')));
      await settle(tester);

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
          child: YaruTheme(
            builder: (context, yaru, child) => MaterialApp(
              theme: yaru.theme,
              darkTheme: yaru.darkTheme,
              home: LinuxHomePage(onCreateIdentity: createIdentity),
            ),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxHomePage)),
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
