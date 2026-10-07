import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/meetings_screen.dart';

import 'pump.dart';

void main() {
  group('mobile meetings flow', () {
    testWidgets('schedule, attend, complete', (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;

      late BuildContext rootContext;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: ShadcnApp(
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

      // Schedule seven days out.
      Navigator.of(rootContext).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileScheduleScreen(groupId: group.id),
        ),
      );
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, '7');
      await tester.tap(find.text('Schedule'));
      await settle(tester);
      expect(find.text('root'), findsOneWidget);

      final meetings = await world.services.meetings.listByGroup(group.id);
      expect(meetings.value, hasLength(1));
      final String meetingId = meetings.value.single.id;

      // Open, flip one attendance, close with a total.
      Navigator.of(rootContext).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileMeetingDetailScreen(
            groupId: group.id,
            meetingId: meetingId,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('0 present'), findsOneWidget);

      await tester.tap(find.text('absent').first);
      await settle(tester);
      expect(find.text('1 present'), findsOneWidget);

      await tester.enterText(find.byType(TextField).first, '200');
      await tester.tap(find.text('Complete meeting'));
      await settle(tester);
      expect(find.text('completed'), findsOneWidget);
    });
  });
}
