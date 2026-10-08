import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/invites_screen.dart';

import 'pump.dart';

void main() {
  group('mobile invites', () {
    testWidgets('creates and lists a live invite', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileInvitesScreen(
              groupId: group.id,
              clock: () => world.now,
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileInvitesScreen)),
      );
      await world.signIn(container);
      await settle(tester);
      expect(find.text('No invites yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('new-invite-button')));
      await settle(tester);

      // The fresh link shows once, with its secret, as text and QR.
      expect(find.textContaining('vbank://join?'), findsOneWidget);
      expect(find.byType(QrImageView), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
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
          child: ShadcnApp(
            home: MobileInvitesScreen(
              groupId: group.id,
              clock: () => world.now,
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileInvitesScreen)),
      );
      await world.signIn(container);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('new-invite-button')));
      await settle(tester);
      expect(find.textContaining('vbank://join?'), findsOneWidget);
      await tester.tap(find.byIcon(LucideIcons.arrowLeft));
      await settle(tester);

      // Tapping the row re-opens the same stored link.
      await tester.tap(find.text('live'));
      await settle(tester);
      expect(find.textContaining('vbank://join?'), findsOneWidget);
    });
  });
}
