import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/report_screen.dart';
import 'package:vbank/src/presentation/providers/reports.dart';

import 'pump.dart';

void main() {
  group('mobile report', () {
    testWidgets('shows metrics, chart and members', (tester) async {
      final setup = await setupGroupWorld();
      for (final String who in ['owner', 'member']) {
        await setup.world.services.transactions.createTransaction(
          groupId: setup.group.id,
          authorPeerId: 'owner',
          fromPeerId: who,
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: who == 'owner' ? 100 : 50,
        );
      }
      await tester.pumpWidget(
        VBankScope(
          repositories: setup.world.repositories,
          services: setup.world.services,
          extraOverrides: [
            reportNowProvider.overrideWithValue(setup.world.now),
          ],
          child: ShadcnApp(
            home: MobileReportScreen(groupId: setup.group.id),
          ),
        ),
      );
      await settle(tester);

      // Metric tiles with formatted amounts.
      expect(find.text('Fund'), findsOneWidget);
      expect(find.text('Contributed'), findsOneWidget);
      expect(find.textContaining('ZK'), findsWidgets);

      // Bar chart plus member rows.
      expect(find.byType(BarChart), findsOneWidget);
      expect(find.text('Owner'), findsWidgets);
      expect(find.text('Member'), findsWidgets);
    });

    testWidgets('switches windows', (tester) async {
      final setup = await setupGroupWorld();
      await setup.world.services.transactions.createTransaction(
        groupId: setup.group.id,
        authorPeerId: 'owner',
        fromPeerId: 'owner',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      );
      await tester.pumpWidget(
        VBankScope(
          repositories: setup.world.repositories,
          services: setup.world.services,
          extraOverrides: [
            reportNowProvider.overrideWithValue(setup.world.now),
          ],
          child: ShadcnApp(
            home: MobileReportScreen(groupId: setup.group.id),
          ),
        ),
      );
      await settle(tester);

      await tester.tap(find.text('Month'));
      await settle(tester);

      expect(find.byType(BarChart), findsOneWidget);
    });
  });
}
