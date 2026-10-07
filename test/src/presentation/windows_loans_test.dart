import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/windows/loans_page.dart';

import 'mobile_loans_test.dart' show qualifyMember;
import 'pump.dart';

void main() {
  group('windows loans flow', () {
    testWidgets('request, approve, disburse, repay to completion',
        (tester) async {
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await qualifyMember(world, group.id);

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
      await world.signIn(container, peer: 'member');
      await settle(tester);

      Navigator.of(rootContext).push(
        fluent.FluentPageRoute<void>(
          builder: (_) => WindowsRequestLoanPage(groupId: group.id),
        ),
      );
      await settle(tester);
      await tester.enterText(find.byType(fluent.TextBox).at(0), '200');
      await tester.enterText(find.byType(fluent.TextBox).at(1), '2');
      await tester.tap(find.text('Send request'));
      await settle(tester);
      expect(find.text('root'), findsOneWidget);

      final loans = await world.services.loans.listByGroup(group.id);
      expect(loans.value, hasLength(1));
      final String loanId = loans.value.single.id;

      final ownerLoans = world.servicesFor('owner').loans;
      await ownerLoans.approveLoan(
        loanId: loanId,
        approvedAmount: 200,
        approverPeerId: 'owner',
      );
      await ownerLoans.disburseLoan(
        loanId: loanId,
        adminPeerId: 'owner',
      );

      await world.signIn(container);
      await settle(tester);
      Navigator.of(rootContext).push(
        fluent.FluentPageRoute<void>(
          builder: (_) => WindowsLoanDetailPage(
            groupId: group.id,
            loanId: loanId,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('disbursed'), findsOneWidget);

      for (var i = 0; i < 2; i++) {
        await tester.enterText(find.byType(fluent.TextBox).first, '110');
        await tester.tap(find.text('Record repayment'));
        await settle(tester);
      }
      expect(find.text('completed'), findsOneWidget);
    });
  });
}
