import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yaru/yaru.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/linux/group_detail_page.dart';
import 'package:vbank/src/presentation/linux/record_page.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('linux group detail', () {
    testWidgets('shows stats and records a contribution', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
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
      await settle(tester);

      expect(find.text('Test Group'), findsOneWidget);
      expect(find.text('Transactions'), findsOneWidget);
      expect(find.text('No transactions yet'), findsOneWidget);

      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxGroupDetailPage)),
      );
      await world.signIn(container);
      await settle(tester);

      // Record a contribution through the form.
      await tester.tap(find.byKey(const ValueKey('record-button')));
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '250');
      await tester.tap(find.text('Save'));
      await settle(tester);

      expect(find.text('contribution · 250.0'), findsOneWidget);
      expect(find.text('250.00'), findsWidgets);
    });
  });

  group('linux record form edges', () {
    testWidgets('rejects empty amounts and explains refusals', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: YaruTheme(
            builder: (context, yaru, child) => MaterialApp(
              theme: yaru.theme,
              darkTheme: yaru.darkTheme,
              home: LinuxRecordPage(groupId: group.id),
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxRecordPage)),
      );
      await world.signIn(container);
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      await settle(tester);

      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Enter an amount above zero.'), findsOneWidget);

      await world.signIn(container, peer: 'member');
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '10');
      await tester.tap(find.text('Save'));
      await settle(tester);
      expect(find.text('Not allowed (notWriter).'), findsOneWidget);
    });
  });
}
