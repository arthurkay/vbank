import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/providers/groups.dart';
import 'package:vbank/src/presentation/windows/member_detail_page.dart';

import 'pump.dart';

void main() {
  group('windows member', () {
    testWidgets('owner promotes a member', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: fluent.FluentApp(
            home: WindowsMemberDetailPage(
              groupId: group.id,
              peerId: 'member',
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(WindowsMemberDetailPage)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      await tester.tap(find.text('Make admin'));
      await settle(tester);

      expect(find.text('Remove admin'), findsOneWidget);
    });
  });
}
