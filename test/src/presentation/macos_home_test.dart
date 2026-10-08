import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/app/invite_link.dart';
import 'package:vbank/src/domain/core/result.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:flutter/cupertino.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/home_page.dart';
import 'package:vbank/src/presentation/macos/onboarding_page.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('macos home', () {
    testWidgets('shows onboarding then groups', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: MacosApp(
            home: MacosHomePage(onCreateIdentity: createIdentity),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(MacosHomePage)),
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

    testWidgets('get started opens onboarding under the macos shell', (
      tester,
    ) async {
      final PresentationWorld world = PresentationWorld();
      // Same composition as main: the shell page pushes its own
      // onboarding page with a live peer id reader.
      Future<void> createIdentity(BuildContext context) =>
          Navigator.push(
            context,
            CupertinoPageRoute<void>(
              builder: (_) => MacosOnboardingPage(
                peerIdOf: () => 'owner',
                publicKey: world.publicKeys['owner']!,
              ),
            ),
          );
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: MacosApp(
            home: Builder(
              builder: (context) => MacosHomePage(
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
      await tester.enterText(find.byType(MacosTextField), 'Amina');
      await tester.tap(find.text('Get started').last);
      await settle(tester);

      expect(find.text('No groups yet'), findsOneWidget);
    });

    testWidgets('creates a group from the empty home', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: MacosApp(
            home: MacosHomePage(onCreateIdentity: createIdentity),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(MacosHomePage)),
      );
      await settle(tester);

      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(find.text('No groups yet'), findsOneWidget);

      await tester.tap(find.text('New group'));
      await settle(tester);
      await tester.enterText(find.byType(MacosTextField).at(0), 'Savings');
      await tester.enterText(find.byType(MacosTextField).at(1), '200');
      await tester.tap(find.text('Create group'));
      await settle(tester);

      // The new group is selected and its detail shows its name.
      expect(container.read(selectedGroupIdProvider), isNotNull);
      expect(find.text('Savings'), findsOneWidget);
    });

    testWidgets('joins a group from a link', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      String? joinedLink;
      String? joinedName;
      Future<Result<Unit>> onJoin({
        required String link,
        required String displayName,
      }) async {
        joinedLink = link;
        joinedName = displayName;
        return const Ok(unit);
      }

      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: MacosApp(
            home: MacosHomePage(
              onCreateIdentity: createIdentity,
              onJoinGroup: onJoin,
            ),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(MacosHomePage)),
      );
      await settle(tester);
      await tester.tap(find.text('Get started'));
      await settle(tester);

      await tester.tap(find.text('Join group'));
      await settle(tester);
      final String link = InviteLink(
        groupId: 'g1',
        groupCid: 'cid-1',
        inviterPeerId: 'owner',
        inviteId: 'id-1',
        secret: Uint8List.fromList(List.filled(32, 7)),
        nonce: Uint8List.fromList(List.filled(16, 7)),
        expiresAt: DateTime.utc(2027, 1, 1),
      ).encode();
      await tester.enterText(find.byType(MacosTextField).at(0), link);
            await tester.tap(find.byKey(const ValueKey('join-submit-button')));
      await settle(tester);

      // The link reached the join callback under the signed-in name, the
      // parsed group is selected and the form popped.
      expect(joinedLink, link);
      expect(joinedName, 'owner');
      expect(container.read(selectedGroupIdProvider), 'g1');
      expect(find.text('Invite link'), findsNothing);
    });
  });
}
