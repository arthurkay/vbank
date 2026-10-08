import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/group_detail_page.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('macos reversal', () {
    testWidgets('request then approve voids the transaction', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
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
          child: MacosApp(
            home: MacosGroupDetailPage(groupId: group.id),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MacosGroupDetailPage)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      await tester.tap(find.textContaining('contribution'));
      await settle(tester);
      await tester.tap(find.text('Request correction'));
      await settle(tester);
      await tester.enterText(find.byType(MacosTextField).last, 'Wrong amount');
      await tester.tap(find.text('Request correction'));
      await settle(tester);
      expect(find.textContaining('Pending'), findsOneWidget);

      expect(find.text('Approve'), findsNothing);

      await world.signIn(container, peer: 'member');
      await settle(tester);
      await tester.tap(find.text('Approve'));
      await settle(tester);
      expect(find.textContaining('Voided'), findsOneWidget);
    });
  });
}
