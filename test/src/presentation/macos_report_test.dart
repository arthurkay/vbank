import 'dart:ui';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/report_page.dart';
import 'package:vbank/src/presentation/providers/reports.dart';

import 'pump.dart';

Future<void> _seedMoney(PresentationWorld world, String groupId) async {
  for (final String who in ['owner', 'member']) {
    await world.services.transactions.createTransaction(
      groupId: groupId,
      authorPeerId: 'owner',
      fromPeerId: who,
      toPeerId: 'group',
      type: TransactionType.contribution,
      amount: who == 'owner' ? 100 : 50,
    );
  }
}

void main() {
  group('macos report', () {
    testWidgets('shows metrics, chart and members', (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final setup = await setupGroupWorld();
      await _seedMoney(setup.world, setup.group.id);
      await tester.pumpWidget(
        VBankScope(
          repositories: setup.world.repositories,
          services: setup.world.services,
          extraOverrides: [
            reportNowProvider.overrideWithValue(setup.world.now),
          ],
          child: MacosApp(
            home: MacosReportPage(groupId: setup.group.id),
          ),
        ),
      );
      await settle(tester);

      expect(find.text('Fund'), findsOneWidget);
      expect(find.text('Contributed'), findsOneWidget);
      expect(find.textContaining('ZK'), findsWidgets);
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Owner'), findsWidgets);
      expect(find.text('Member'), findsWidgets);
    });
  });
}
