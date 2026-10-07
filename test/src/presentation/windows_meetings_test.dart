import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/windows/meetings_page.dart';

import 'pump.dart';

void main() {
  group('windows meetings flow', () {
    testWidgets('schedule, attend, complete', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;

      late BuildContext rootContext;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: fluent.FluentApp(
            home: Builder(
              builder: (context) {
                rootContext = context;
                return const Text('root');
              },
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.text('root')),
      );
      await world.signIn(container);
      await settle(tester);

      Navigator.of(rootContext).push(
        fluent.FluentPageRoute<void>(
          builder: (_) => WindowsSchedulePage(groupId: group.id),
        ),
      );
      await settle(tester);
      await tester.enterText(find.byType(fluent.TextBox).first, '7');
      await tester.tap(find.text('Schedule'));
      await settle(tester);
      expect(find.text('root'), findsOneWidget);

      final meetings = await world.services.meetings.listByGroup(group.id);
      expect(meetings.value, hasLength(1));
      final String meetingId = meetings.value.single.id;

      Navigator.of(rootContext).push(
        fluent.FluentPageRoute<void>(
          builder: (_) => WindowsMeetingDetailPage(
            groupId: group.id,
            meetingId: meetingId,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('0 present · scheduled'), findsOneWidget);

      await tester.tap(find.text('Flip').first);
      await settle(tester);
      expect(find.text('1 present · scheduled'), findsOneWidget);

      await tester.enterText(find.byType(fluent.TextBox).first, '200');
      await tester.tap(find.text('Complete meeting'));
      await settle(tester);
      expect(find.textContaining('completed'), findsWidgets);
    });
  });
}
