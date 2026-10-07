import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/group_detail_page.dart';
import 'package:vbank/src/presentation/macos/record_page.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('macos group detail', () {
    testWidgets('shows stats and records a contribution', (tester) async {
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
      await settle(tester);

      expect(find.text('Test Group'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('No transactions yet'), findsOneWidget);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MacosGroupDetailPage)),
      );
      await world.signIn(container);
      await settle(tester);

      // Record a contribution through the form.
      final Finder recordIcon = find.byWidgetPredicate(
        (Widget w) => w is MacosIcon && w.icon == CupertinoIcons.add,
      );
      expect(recordIcon, findsOneWidget);
      await tester.tap(recordIcon);
      await settle(tester);
      await tester.enterText(find.byType(MacosTextField).first, '250');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('contribution · 250.0'), findsOneWidget);
      expect(find.text('250.00'), findsWidgets);
    });
  });

  group('macos record form edges', () {
    testWidgets('rejects empty amounts and explains refusals', (tester) async {
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
            home: MacosRecordPage(groupId: group.id),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(MacosRecordPage)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Enter an amount above zero.'), findsOneWidget);

      await world.signIn(container, peer: 'member');
      await settle(tester);
      await tester.enterText(find.byType(MacosTextField).first, '10');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Not allowed (notWriter).'), findsOneWidget);
    });
  });
}
