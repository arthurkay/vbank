import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/providers/groups.dart';
import 'package:vbank/src/presentation/windows/group_detail_page.dart';

import 'pump.dart';

void main() {
  group('windows sync', () {
    testWidgets('opens from detail without a coordinator', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: fluent.FluentApp(
            home: WindowsGroupDetailPage(groupId: group.id),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(WindowsGroupDetailPage)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      await tester.scrollUntilVisible(find.text('Sync'), 100);
      await settle(tester);
      await tester.tap(find.text('Sync'));
      await settle(tester);

      // State unknown, no relays, inert Sync button — but no crash.
      expect(find.text('None configured.'), findsOneWidget);
      await tester.tap(find.text('Sync now'));
      await settle(tester);
      expect(find.text('None configured.'), findsOneWidget);
    });
  });
}
