import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/linux/member_detail_page.dart';
import 'package:vbank/src/presentation/providers/groups.dart';
import 'package:yaru/yaru.dart';

import 'pump.dart';

void main() {
  group('linux member', () {
    testWidgets('owner promotes a member', (tester) async {
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
              home: LinuxMemberDetailPage(
                groupId: group.id,
                peerId: 'member',
              ),
            ),
          ),
        ),
      );
      final ProviderContainer container = ProviderScope.containerOf(
        tester.element(find.byType(LinuxMemberDetailPage)),
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
