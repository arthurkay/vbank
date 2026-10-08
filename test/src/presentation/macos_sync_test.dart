import 'dart:ui';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/group_detail_page.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('macos sync', () {
    testWidgets('opens from detail without a coordinator', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
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
