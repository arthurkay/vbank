import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/member_detail_screen.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('mobile member', () {
    testWidgets('owner promotes a member', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileMemberDetailScreen(
              groupId: group.id,
              peerId: 'member',
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileMemberDetailScreen)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      expect(find.text('Member'), findsWidgets);
      expect(find.text('member'), findsWidgets);

      await tester.tap(find.text('Make admin'));
      await settle(tester);

      expect(find.text('Remove admin'), findsOneWidget);
    });

    testWidgets('members see no actions', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
            home: MobileMemberDetailScreen(
              groupId: group.id,
              peerId: 'owner',
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MobileMemberDetailScreen)),
      );
      await world.signIn(container, peer: 'member');
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      expect(find.text('Make admin'), findsNothing);
      expect(find.text('Remove'), findsNothing);
    });
  });
}
