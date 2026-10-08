import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/group_detail_screen.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('mobile reversal', () {
    testWidgets('request then approve voids the transaction', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await world.services.transactions.createTransaction(
        groupId: group.id,
        authorPeerId: 'owner',
        fromPeerId: 'owner',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      );
      // A second admin so someone else than the requester can decide.
      final withAdmin = (await world.services.groups.getGroup(group.id)).value;
      await world.services.groups.updateMemberRole(
        group: withAdmin,
        actingPeerId: 'owner',
        peerId: 'member',
        newRole: MemberRole.admin,
      );
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
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      // Open the transaction, request a correction.
      await tester.tap(find.textContaining('contribution'));
      await settle(tester);
      await tester.tap(find.text('Request correction'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Wrong amount');
      await tester.tap(find.text('Request correction').last);
      await settle(tester);
      expect(find.textContaining('Pending'), findsOneWidget);

      // The requester cannot approve their own request.
      expect(find.text('Approve'), findsNothing);

      // An admin approves: the transaction voids.
      await world.signIn(container, peer: 'member');
      await settle(tester);
      await tester.tap(find.text('Approve'));
      await settle(tester);
      expect(find.textContaining('Voided'), findsOneWidget);
    });
  });
}
