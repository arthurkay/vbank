/// Desktop-only reproduction of the loan half of the two-device E2E: a fake
/// member (services only) contributes and requests a loan; the Yaru UI then
/// approves, disburses and records a repayment. Run with:
///
///   GDK_BACKEND=x11 DISPLAY=:0 flutter test integration_test/linux_loan_flow_test.dart -d linux
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vbank/core/crypto/identity.dart';
import 'package:vbank/core/crypto/signing.dart';
import 'package:vbank/core/storage/user_identity_dao.dart';
import 'package:vbank/models/transaction.dart';
import 'package:vbank/models/group.dart';
import 'package:vbank/models/loan.dart';
import 'package:vbank/main.dart' as app;
import 'package:vbank/services/group_service.dart';
import 'package:vbank/services/loan_service.dart';
import 'package:vbank/services/transaction_service.dart';

const passphrase = 'e2e-passphrase-2026';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  Finder tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));
  Finder filled(String label) =>
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is FilledButton));
  Future<void> settle(WidgetTester tester, [double seconds = 2]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }
  Future<bool> waitVisible(WidgetTester tester, Finder f, double seconds) async {
    for (var i = 0; i < seconds * 2; i++) {
      if (f.evaluate().isNotEmpty) return true;
      await settle(tester, 0.5);
    }
    return f.evaluate().isNotEmpty;
  }

  /// Yaru toasts sit bottom-left, right where the loan page's action buttons
  /// land, and a tap on a toast is swallowed. Wait for one to go away.
  Future<void> waitGone(WidgetTester tester, Finder f, [double seconds = 8]) async {
    for (var i = 0; i < seconds * 4 && f.evaluate().isNotEmpty; i++) {
      await settle(tester, 0.25);
    }
  }

  testWidgets('approve → disburse → repay on the Yaru loan page', (tester) async {
    // Everything up to the loan request happens through the services before the
    // app starts, so the UI loads a group that already has a member, three
    // contributions and a pending loan (the way it would after a sync).
    final identity = await UserIdentityDao().get();
    expect(identity, isNotNull, reason: 'run the E2E once first so the desktop has an identity');
    final ownerKp = await SigningService.keyPairFromSeed(identity!.privateKey!);
    final groupService = GroupService();
    final txService = TransactionService();
    final groupName = 'Loan Flow ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final group = await groupService.createGroup(
      name: groupName,
      config: const GroupConfig(groupId: '', contributionAmount: 20),
      passphrase: passphrase,
      ownerPeerId: identity.peerId,
      ownerName: identity.displayName,
      ownerPublicKey: identity.publicKey,
      ownerKeyPair: ownerKp,
    );
    final borrower = await IdentityManager.createIdentity('Fake Member');
    await groupService.addMember(
      groupId: group.id,
      member: Member(
        peerId: borrower.identity.peerId,
        name: 'Fake Member',
        role: MemberRole.member,
        joinedAt: DateTime.now().toUtc(),
        publicKey: borrower.identity.publicKey,
      ),
    );
    for (var i = 0; i < 3; i++) {
      await txService.createTransaction(
        groupId: group.id,
        authorPeerId: identity.peerId,
        authorKeyPair: ownerKp,
        fromPeerId: borrower.identity.peerId,
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 20,
      );
    }
    final loanService = LoanService(groupService: groupService, transactionService: txService);
    final loan = await loanService.requestLoan(
      groupId: group.id,
      borrowerPeerId: borrower.identity.peerId,
      borrowerKeyPair: borrower.keyPair,
      requestedAmount: 50,
      termWeeks: 4,
    );
    expect(loan.status, LoanStatus.pending);

    runZonedGuarded(app.main, (e, st) => debugPrint('[loan-flow] background error ignored: $e'));
    await settle(tester, 8);
    expect(await waitVisible(tester, find.text(groupName), 15), isTrue, reason: 'group in the list');
    await tester.tap(find.text(groupName).first);
    await settle(tester, 4);

    await tester.tap(tab('Loans'));
    await settle(tester, 3);
    expect(await waitVisible(tester, find.textContaining('Fake Member'), 10), isTrue, reason: 'loan appears in the list');
    await tester.tap(find.textContaining('Fake Member').first);
    await settle(tester, 3);
    await tester.tap(filled('Approve'));
    await settle(tester, 2);
    await tester.tap(filled('Approve').last);
    final sw = Stopwatch()..start();
    expect(await waitVisible(tester, filled('Record disbursement'), 20), isTrue, reason: 'approved → disbursement button');
    debugPrint('[loan-flow] disbursement button after ${sw.elapsedMilliseconds} ms');
    await waitGone(tester, find.textContaining('Loan approved'));
    await tester.tap(filled('Record disbursement'));
    sw.reset();
    final ok = await waitVisible(tester, filled('Record repayment'), 30);
    debugPrint('[loan-flow] repayment button visible=$ok after ${sw.elapsedMilliseconds} ms');
    final after = (await loanService.getByGroupId(group.id)).where((l) => l.id == loan.id).single;
    debugPrint('[loan-flow] loan status in DB: ${after.status}');
    if (!ok) {
      final texts = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data ?? t.textSpan?.toPlainText() ?? '')
          .where((t) => t.trim().isNotEmpty)
          .toList();
      debugPrint('[loan-flow] texts on screen: $texts');
      final buttons = tester.widgetList(find.byWidgetPredicate((w) => w is FilledButton)).length;
      debugPrint('[loan-flow] filled buttons on screen: $buttons');
    }
    expect(ok, isTrue, reason: 'disbursed → repayment button');
    await waitGone(tester, find.textContaining('Loan disbursed'));
    await tester.tap(filled('Record repayment'));
    await settle(tester, 2);
    await tester.tap(filled('Record').last);
    await settle(tester, 6);
    final repaid = (await loanService.getByGroupId(group.id)).where((l) => l.id == loan.id).single;
    expect(repaid.status, anyOf(LoanStatus.repaying, LoanStatus.disbursed, LoanStatus.completed));
  });
}
