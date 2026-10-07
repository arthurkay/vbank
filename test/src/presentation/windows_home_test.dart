import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/windows/home_page.dart';

import 'pump.dart';

void main() {
  group('windows home', () {
    testWidgets('shows onboarding then groups', (tester) async {
      final PresentationWorld world = PresentationWorld();
      late ProviderContainer container;
      Future<void> createIdentity() => world.signIn(container);
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: fluent.FluentApp(
            home: WindowsHomePage(onCreateIdentity: createIdentity),
          ),
        ),
      );
      container = ProviderScope.containerOf(
        tester.element(find.byType(WindowsHomePage)),
      );
      await settle(tester);

      expect(find.text('Get started'), findsOneWidget);

      await tester.tap(find.text('Get started'));
      await settle(tester);
      expect(find.text('No groups yet'), findsOneWidget);

      await world.services.groups.createGroup(
        name: 'Test Group',
        config: const GroupConfig(
          groupId: 'template',
          contributionAmount: 100,
          meetingTime: MeetingTime(hour: 9, minute: 0),
        ),
        ownerPeerId: 'owner',
        ownerName: 'Owner',
        ownerPublicKey: world.publicKeys['owner']!,
      );
      await settle(tester);
      expect(find.text('Test Group'), findsOneWidget);
    });
  });
}
