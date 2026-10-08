import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/group_detail_screen.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('mobile sync', () {
    testWidgets('opens from detail without a coordinator', (tester) async {
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
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
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
