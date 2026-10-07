import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:vbank/src/domain/transactions.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/mobile/loans_screen.dart';

import 'pump.dart';

/// Qualifies `member` with three contributions through the owner stack.
Future<String> qualifyMember(PresentationWorld world, String gid) async {
  for (var i = 0; i < 3; i++) {
    await world.services.transactions.createTransaction(
      groupId: gid,
      authorPeerId: 'owner',
      fromPeerId: 'member',
      toPeerId: 'group',
      type: TransactionType.contribution,
      amount: 100,
    );
  }
  return gid;
}

void main() {
  group('mobile loans flow', () {
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
          child: ShadcnApp(
            home: Builder(
              builder: (BuildContext context) {
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

      // Request as the member.
      Navigator.of(rootContext).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileRequestLoanScreen(groupId: group.id),
        ),
      );
      await settle(tester);
      await tester.enterText(find.byType(TextField).at(0), '200');
      await tester.enterText(find.byType(TextField).at(1), '2');
      await tester.tap(find.text('Send request'));
      await settle(tester);
      expect(find.text('root'), findsOneWidget);

      final loans = await world.services.loans.listByGroup(group.id);
      expect(loans.value, hasLength(1));
      final String loanId = loans.value.single.id;

      // Approve and disburse as the owner (service level).
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

      // Repayments need a writer: switch to the owner identity.
      await world.signIn(container);
      await settle(tester);

      // Detail shows the schedule; repay twice to complete.
      Navigator.of(rootContext).push(
        MaterialPageRoute<void>(
          builder: (_) => MobileLoanDetailScreen(
            groupId: group.id,
            loanId: loanId,
          ),
        ),
      );
      await settle(tester);
      expect(find.text('disbursed'), findsOneWidget);

      for (var i = 0; i < 2; i++) {
        await tester.enterText(find.byType(TextField).first, '110');
        await tester.tap(find.text('Record repayment'));
        await settle(tester);
      }
      expect(find.text('completed'), findsOneWidget);
    });
  });
}
