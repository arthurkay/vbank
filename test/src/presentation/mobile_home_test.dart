import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/domain/core/result.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/app/invite_link.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/home_screen.dart';
import 'package:vbank/src/presentation/onboarding/onboarding_screen.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('mobile home', () {
    testWidgets('shows onboarding then groups', (tester) async {
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

      await tester.tap(find.text('Test Group'));
      await settle(tester);
      expect(container.read(selectedGroupIdProvider), isNotNull);
    });

    testWidgets('get started opens onboarding under the mobile shell', (
      tester,
    ) async {
      final PresentationWorld world = PresentationWorld();
      // Same composition as main: a Builder below the app root gives the
      // push a context with a Navigator.
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: Builder(
              builder: (context) => MobileHomeScreen(
                onCreateIdentity: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => OnboardingScreen(
                      peerIdOf: () => 'owner',
                      publicKey: world.publicKeys['owner']!,
                    ),
                  ),
                ),
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
      await tester.enterText(find.byType(TextField), 'Amina');
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
      expect(find.text('No groups yet'), findsOneWidget);

      await tester.tap(find.text('New group'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(0), 'Savings');
      await tester.enterText(find.byType(TextField).at(1), '200');
      await tester.tap(find.text('Create group'));
      await settle(tester);

      // The detail opens with a record action.
      expect(find.byKey(const ValueKey('record-button')), findsOneWidget);
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
          child: ShadcnApp(
            home: MobileHomeScreen(
              onCreateIdentity: createIdentity,
              onJoinGroup: onJoin,
            ),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(MobileHomeScreen)),
      );
      await settle(tester);
      await tester.tap(find.text('Get started'));
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('join-group-button')));
      await settle(tester);
      final String link = InviteLink(
        groupId: 'g1',
        groupCid: 'cid-1',
        groupTopic: 'vbank/group/g1',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        inviteId: 'id-1',
        secret: Uint8List.fromList(List.filled(32, 7)),
        nonce: Uint8List.fromList(List.filled(16, 7)),
        expiresAt: DateTime.utc(2027, 1, 1),
      ).encode();
      await tester.enterText(find.byType(TextField).at(0), link);
      await tester.enterText(find.byType(TextField).at(1), 'Amina');
      await tester.tap(find.byKey(const ValueKey('join-submit-button')));
      await settle(tester);

      // The link and name reached the join callback, the parsed group
      // is selected and the form popped.
      expect(joinedLink, link);
      expect(joinedName, 'Amina');
      expect(container.read(selectedGroupIdProvider), 'g1');
      expect(find.text('Invite link'), findsNothing);
    });
  });
}
