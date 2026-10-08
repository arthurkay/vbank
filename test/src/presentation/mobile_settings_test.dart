import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/group_detail_screen.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('mobile settings', () {
    testWidgets('owner transfers to an admin', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
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

      await tester.scrollUntilVisible(find.text('Settings'), 100);
      await settle(tester);
      await tester.tap(find.text('Settings'));
      await settle(tester);

      // Pick the admin, confirm twice, roles flip.
      await tester.tap(find.text('Member').last);
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('transfer-button')));
      await settle(tester);
      await tester.tap(find.byKey(const ValueKey('transfer-button')));
      await settle(tester);

      final updated =
          (await world.services.groups.getGroup(group.id)).value;
      MemberRole roleOf(String peer) => updated.members
          .firstWhere((m) => m.peerId == peer)
          .role;
      expect(roleOf('member'), MemberRole.owner);
      expect(roleOf('owner'), MemberRole.admin);
    });

    testWidgets('members see no settings entry', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
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
      await world.signIn(container, peer: 'member');
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      expect(find.text('Settings'), findsNothing);
    });
  });
}
