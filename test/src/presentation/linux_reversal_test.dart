import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/linux/group_detail_page.dart';
import 'package:vbank/src/presentation/providers/groups.dart';
import 'package:yaru/yaru.dart';

import 'pump.dart';

void main() {
  group('linux reversal', () {
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
          child: YaruTheme(
            builder: (context, yaru, child) => MaterialApp(
              theme: yaru.theme,
              darkTheme: yaru.darkTheme,
              home: LinuxGroupDetailPage(groupId: group.id),
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxGroupDetailPage)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      await tester.tap(find.textContaining('contribution'));
      await settle(tester);
      await tester.tap(find.text('Request correction'));
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'Wrong amount');
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
