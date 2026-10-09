import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
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
      expect(find.text('AVAILABLE TO LEND'), findsOneWidget);
      expect(find.text('Members'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tab-activity')));
      await settle(tester);
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

      expect(find.textContaining('contribution'), findsOneWidget);
      expect(find.text('250.0'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('tab-overview')));
      await settle(tester);
      expect(find.text('250.00'), findsWidgets);
    });

    testWidgets('bottom nav switches sections', (tester) async {      final setup = await setupGroupWorld();
      final Group group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: setup.world.repositories,
          services: setup.world.services,
          child: ShadcnApp(
            home: MobileGroupDetailScreen(groupId: group.id),
          ),
        ),
      );
      await settle(tester);

      // Five equal destinations, overview first.
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('Loans'), findsOneWidget);
      expect(find.text('Meetings'), findsOneWidget);
      expect(find.text('More'), findsOneWidget);
      expect(find.text('AVAILABLE TO LEND'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tab-loans')));
      await settle(tester);
      expect(find.text('No loans yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tab-meetings')));
      await settle(tester);
      expect(find.text('No meetings yet'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('tab-more')));
      await settle(tester);
      expect(find.text('Sync'), findsOneWidget);
      expect(find.text('Reports'), findsOneWidget);
    });

    testWidgets('switcher lists groups and switches', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final Group group = setup.group;
      final Group second =
          (await world.services.groups.createGroup(
            name: 'Second',
            config: const GroupConfig(
              groupId: 'template',
              contributionAmount: 50,
              meetingTime: MeetingTime(hour: 9, minute: 0),
            ),
            ownerPeerId: 'owner',
            ownerName: 'Owner',
            ownerPublicKey: world.publicKeys['owner']!,
          )).value;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileGroupDetailScreen(groupId: group.id),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileGroupDetailScreen)),
      );
      await world.signIn(container);
      await settle(tester);

      await tester.tap(find.byKey(const ValueKey('group-switcher')));
      await settle(tester);
      expect(find.text('Switch group'), findsOneWidget);
      expect(find.text('Second'), findsOneWidget);

      await tester.tap(find.text('Second'));
      await settle(tester);
      expect(container.read(selectedGroupIdProvider), second.id);
    });

    testWidgets('quick actions match the role', (tester) async {
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
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileGroupDetailScreen)),
      );
      await world.signIn(container);
      await settle(tester);
      expect(find.text('Record'), findsOneWidget);
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Invite'), findsOneWidget);

      await world.signIn(container, peer: 'member');
      await settle(tester);
      expect(find.text('Record'), findsNothing);
      expect(find.text('Request'), findsOneWidget);
      expect(find.text('Invite'), findsNothing);
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

      // Plain members never reach the form: writers-only notice instead.
      await world.signIn(container, peer: 'member');
      await settle(tester);
      expect(
        find.text('Only owners and admins record transactions.'),
        findsOneWidget,
      );
      expect(find.text('Save'), findsNothing);
    });
  });
}
