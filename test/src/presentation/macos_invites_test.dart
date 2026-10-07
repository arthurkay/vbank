import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/app/invite_link.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/invites_page.dart';

import 'pump.dart';

void main() {
  group('macos invites', () {
    testWidgets('creates and lists a live invite', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: MacosApp(
            home: MacosInvitesPage(groupId: group.id, clock: () => world.now),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MacosInvitesPage)),
      );
      await world.signIn(container);
      await settle(tester);
      expect(find.text('No invites yet'), findsOneWidget);

      // The toolbar button is a ToolbarItem, not a widget: tap by key
      // through the rendered control is unreliable, so drive creation
      // through the service and assert the list follows.
      expect(find.byKey(const ValueKey('new-invite-button')), findsNothing);
      await world.services.invites.createInvite(
        groupId: group.id,
        groupCid: '',
        groupTopic: 'vbank/group/${group.id}',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        groupKey: (await world.services.keys.requireKey(group.id)).value,
      );
      await settle(tester);

      expect(find.text('No invites yet'), findsNothing);
      expect(find.text('live'), findsOneWidget);
    });

    testWidgets('re-shares a live invite from its row', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: MacosApp(
            home: MacosInvitesPage(groupId: group.id, clock: () => world.now),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MacosInvitesPage)),
      );
      await world.signIn(container);
      await settle(tester);

      // The toolbar button is not tappable in tests: create through the
      // service, then store the link exactly like _create does.
      final created = (await world.services.invites.createInvite(
        groupId: group.id,
        groupCid: '',
        groupTopic: 'vbank/group/${group.id}',
        inviterPeerId: 'owner',
        inviterName: 'Owner',
        groupKey: (await world.services.keys.requireKey(group.id)).value,
      ))
          .value;
      const String link = 'vbank://join?stored-link';
      await InviteLink.storeLink(
        world.settingsRepo,
        created.invite.id,
        link,
      );
      await settle(tester);

      // Tapping the row re-opens the stored link.
      await tester.tap(find.text('live'));
      await settle(tester);
      expect(find.text(link), findsOneWidget);
    });
  });
}
