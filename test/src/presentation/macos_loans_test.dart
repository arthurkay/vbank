import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/macos/loans_page.dart';

import 'mobile_loans_test.dart' show qualifyMember;
import 'pump.dart';

void main() {
  group('macos loans flow', () {
    testWidgets('request, approve, disburse, repay to completion',
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final setup = await setupGroupWorld();
      final PresentationWorld world = setup.world;
      final group = setup.group;
      await qualifyMember(world, group.id);

      late BuildContext rootContext;
      await tester.pumpWidget(
        VBankScope(
          repositories: world.repositories,
          services: world.services,
          child: MacosApp(
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
        CupertinoPageRoute<void>(
          builder: (_) => MacosRequestLoanPage(groupId: group.id),
        ),
      );
      await settle(tester);
      await tester.enterText(find.byType(MacosTextField).at(0), '200');
      await tester.enterText(find.byType(MacosTextField).at(1), '2');
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
        CupertinoPageRoute<void>(
          builder: (_) => MacosLoanDetailPage(
            groupId: group.id,
            loanId: loanId,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('disbursed'), findsOneWidget);

      for (var i = 0; i < 2; i++) {
        await tester.enterText(find.byType(MacosTextField).first, '110');
        await tester.tap(find.text('Record repayment'));
        await settle(tester);
      }
      expect(find.text('completed'), findsOneWidget);
    });
  });
}
