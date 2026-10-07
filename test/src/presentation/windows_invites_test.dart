import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/windows/invites_page.dart';

import 'pump.dart';

void main() {
  group('windows invites', () {
    testWidgets('creates and lists a live invite', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: fluent.FluentApp(
            home: WindowsInvitesPage(groupId: group.id, clock: () => world.now),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(WindowsInvitesPage)),
      );
      await world.signIn(container);
      await settle(tester);
      expect(find.text('No invites yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('new-invite-button')));
      await settle(tester);

      // The fresh link shows once, with its secret; back reveals the row.
      expect(find.textContaining('vbank://join?'), findsOneWidget);
      await tester.tap(find.byIcon(fluent.FluentIcons.back));
      await settle(tester);
      expect(find.textContaining('vbank://join?'), findsNothing);

      expect(find.text('No invites yet'), findsNothing);
      expect(find.text('live'), findsOneWidget);
    });
  });
}
