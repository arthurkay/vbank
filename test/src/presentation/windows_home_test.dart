import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:flutter/material.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/windows/home_page.dart';
import 'package:vbank/src/presentation/windows/onboarding_page.dart';

import 'pump.dart';

void main() {
  group('windows home', () {
    testWidgets('shows onboarding then groups', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: fluent.FluentApp(
            home: WindowsHomePage(onCreateIdentity: createIdentity),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(WindowsHomePage)),
      );
      await settle(tester);

      expect(find.text('Get started'), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(find.text('No groups yet'), findsOneWidget);

      await world.services.groups.createGroup(
        name: 'Test Group',
        config: const GroupConfig(
          groupId: 'template',
          contributionAmount: 100,
          meetingTime: MeetingTime(hour: 9, minute: 0),
        ),
        ownerPeerId: 'owner',
        ownerName: 'Owner',
        ownerPublicKey: world.publicKeys['owner']!,
      );
      await settle(tester);
      expect(find.text('Test Group'), findsOneWidget);
    });

    testWidgets('get started opens onboarding under the windows shell', (
      tester,
    ) async {
      final PresentationWorld world = PresentationWorld();
      // Same composition as main: the shell page pushes its own
      // onboarding page with a live peer id reader.
      Future<void> createIdentity(BuildContext context) =>
          Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => WindowsOnboardingPage(
                peerIdOf: () => 'owner',
                publicKey: world.publicKeys['owner']!,
              ),
            ),
          );
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: fluent.FluentApp(
            home: Builder(
              builder: (context) => WindowsHomePage(
                onCreateIdentity: () => createIdentity(context),
              ),
            ),
          ),
        ),
      );
      await world.publicKeyFor('owner');
      await settle(tester);

      await tester.tap(find.text('Get started'));
      await settle(tester);

      // The onboarding form is up and completes the sign-in.
      expect(find.text('Your name'), findsOneWidget);
      await tester.enterText(find.byType(fluent.TextBox), 'Amina');
      await tester.tap(find.text('Get started').last);
      await settle(tester);

      expect(find.text('No groups yet'), findsOneWidget);
    });
  });
}
