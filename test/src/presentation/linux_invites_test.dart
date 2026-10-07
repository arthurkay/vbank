import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/linux/invites_page.dart';

import 'pump.dart';

void main() {
  group('linux invites', () {
    testWidgets('creates and lists a live invite', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: YaruTheme(
            builder: (context, yaru, child) => MaterialApp(
              theme: yaru.theme,
              darkTheme: yaru.darkTheme,
              home: LinuxInvitesPage(groupId: group.id, clock: () => world.now),
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxInvitesPage)),
      );
      await world.signIn(container);
      await settle(tester);
      expect(find.text('No invites yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('new-invite-button')));
      await settle(tester);

      // The fresh link shows once, with its secret; back reveals the row.
      expect(find.textContaining('vbank://join?'), findsOneWidget);
      await tester.tap(find.byType(YaruBackButton));
      await settle(tester);
      expect(find.textContaining('vbank://join?'), findsNothing);

      expect(find.text('No invites yet'), findsNothing);
      expect(find.text('live'), findsOneWidget);
    });

    testWidgets('re-shares a live invite from its row', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: YaruTheme(
            builder: (context, yaru, child) => MaterialApp(
              theme: yaru.theme,
              darkTheme: yaru.darkTheme,
              home: LinuxInvitesPage(groupId: group.id, clock: () => world.now),
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxInvitesPage)),
      );
      await world.signIn(container);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('new-invite-button')));
      await settle(tester);
      expect(find.textContaining('vbank://join?'), findsOneWidget);
      await tester.tap(find.byType(YaruBackButton));
      await settle(tester);

      // Tapping the row re-opens the same stored link.
      await tester.tap(find.text('live'));
      await settle(tester);
      expect(find.textContaining('vbank://join?'), findsOneWidget);
    });

    testWidgets('a spent invite explains instead of sharing', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: YaruTheme(
            builder: (context, yaru, child) => MaterialApp(
              theme: yaru.theme,
              darkTheme: yaru.darkTheme,
              home: LinuxInvitesPage(groupId: group.id, clock: () => world.now),
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxInvitesPage)),
      );
      await world.signIn(container);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('new-invite-button')));
      await settle(tester);
      await tester.tap(find.byType(YaruBackButton));
      await settle(tester);

      // Spend the ticket, then tap its row.
      final invites = await world.inviteRepo.listByGroup(group.id);
      await world.services.invites.markUsed(invites.value.first.id);
      await settle(tester);
      await tester.tap(find.text('used'));
      await settle(tester);

      expect(find.textContaining('already used'), findsOneWidget);
      expect(find.textContaining('vbank://join?'), findsNothing);
    });
  });
}
