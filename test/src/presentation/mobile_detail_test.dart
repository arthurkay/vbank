import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/group_detail_screen.dart';
import 'package:vbank/src/presentation/mobile/record_screen.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('mobile group detail', () {
    testWidgets('shows stats and records a contribution', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final Group group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileGroupDetailScreen(groupId: group.id),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Test Group'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('No transactions yet'), findsOneWidget);

      // Record a contribution through the form (signed in as the owner).
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileGroupDetailScreen)),
      );
      await world.signIn(container);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('record-button')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '250');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('contribution · 250.0'), findsOneWidget);
      expect(find.text('250.00'), findsWidgets);
    });
  });

  group('mobile record form edges', () {
    testWidgets('rejects empty amounts and explains refusals', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final Group group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileRecordScreen(groupId: group.id),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileRecordScreen)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      // Empty amount: local validation, no service call.
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Enter an amount above zero.'), findsOneWidget);

      // Plain members are refused with an explanation.
      await world.signIn(container, peer: 'member');
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Not allowed (notWriter).'), findsOneWidget);
    });
  });
}
