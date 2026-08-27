/// Desktop half of a two-device village-banking run.
///
/// The Linux (Yaru) app plays the group owner; a phone running the mobile
/// build plays an ordinary member. The two only talk through vBank's own
/// peer-to-peer sync — no test hooks. This test drives the desktop UI and
/// coordinates with whoever is driving the phone through files in `E2E_DIR`:
///
///   stage        what the desktop has just done / is waiting on
///   invite.txt   the vbank://join link for the phone to open
///   group.txt    the new group's id
///   summary.json written at the end with what was observed
///
/// Everything the desktop "sees" from the phone (a join request, a loan
/// request) arrives via IPFS pubsub, so those waits are the real assertions.
///
/// Run with:
///   E2E_DIR=/path GDK_BACKEND=x11 flutter test integration_test/e2e_desktop_peer_test.dart -d linux
/// and drive the phone with `tool/e2e/phone.sh` (deeplink → passphrase, then
/// once `stage` is `contributed`: opengroup → loan). The phone should run a
/// profile build; the desktop test writes `name.txt` so the driver can find the
/// group by name.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vbank/core/storage/settings_dao.dart';
import 'package:vbank/main.dart' as app;
import 'package:vbank/models/group.dart';
import 'package:vbank/models/loan.dart';
import 'package:vbank/services/group_service.dart';
import 'package:vbank/services/loan_service.dart';
import 'package:vbank/services/meeting_service.dart';
import 'package:vbank/services/transaction_service.dart';
import 'package:yaru/yaru.dart';

const passphrase = 'e2e-passphrase-2026';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  final dir = Directory(Platform.environment['E2E_DIR'] ?? '/tmp/vbank-e2e');
  void stage(String s) {
    dir.createSync(recursive: true);
    File('${dir.path}/stage').writeAsStringSync(s);
    // ignore: avoid_print
    print('[e2e] stage=$s');
  }

  /// Tab labels can collide with sidebar destinations ("Meetings"), so scope to the tab bar.
  Finder tab(String label) => find.descendant(of: find.byType(TabBar), matching: find.text(label));

  /// `FilledButton.icon` builds a private subclass, so match by `is`, not by type.
  Finder filled(String label) =>
      find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is FilledButton));

  Future<void> settle(WidgetTester tester, [double seconds = 2]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Yaru toasts sit bottom-left, right where the loan page's action buttons
  /// land, and a tap on a toast is swallowed. Wait for one to go away.
  Future<void> waitGone(WidgetTester tester, Finder f, [double seconds = 8]) async {
    for (var i = 0; i < seconds * 4 && f.evaluate().isNotEmpty; i++) {
      await settle(tester, 0.25);
    }
  }

  /// Polls [probe] until it returns non-null or [timeout] passes, pumping the
  /// UI meanwhile so sync callbacks and rebuilds keep flowing.
  Future<T?> waitFor<T>(WidgetTester tester, Future<T?> Function() probe, Duration timeout, String what) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      final v = await probe();
      if (v != null) return v;
      await settle(tester, 2);
    }
    // ignore: avoid_print
    print('[e2e] TIMEOUT waiting for $what');
    return null;
  }

  testWidgets('owner on desktop, member on phone: join → approve → contribute → loan → meeting',
      (tester) async {
    // dart_ipfs/ipfs_libp2p leak the occasional async StateError ("Session
    // closed while opening stream") when a peer drops a connection. The app
    // shrugs those off; the test framework would fail the test, so contain them.
    // E2E_RELAY=/ip4/…/tcp/4001/p2p/… makes the owner use a relay node; the
    // invite link then carries it and the phone configures itself.
    final relay = Platform.environment['E2E_RELAY'];
    if (relay != null && relay.isNotEmpty) {
      await SettingsDao().set(SettingKeys.relayAddrs, jsonEncode([relay]));
      // ignore: avoid_print
      print('[e2e] relay configured: $relay');
    }
    runZonedGuarded(app.main, (e, st) {
      // ignore: avoid_print
      print('[e2e] background error ignored: $e');
    });
    await settle(tester, 6);

    // --- identity (first run only) --------------------------------------------
    final getStarted = filled('Get started');
    if (getStarted.evaluate().isNotEmpty) {
      await tester.tap(getStarted);
      await settle(tester);
      await tester.enterText(find.byType(TextField).first, 'Desktop Owner');
      await settle(tester);
      await tester.tap(filled('Get started').last);
      await settle(tester, 5);
    }

    // --- create the group (approval required, so the phone's join is gated) ---
    final groupName = 'E2E Circle ${DateTime.now().millisecondsSinceEpoch % 100000}';
    await tester.tap(filled('New group').first);
    await settle(tester);
    // Scope to the dialog: with 6+ groups the list shows a YaruSearchField too.
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    await tester.enterText(fields.at(0), groupName);
    await tester.enterText(fields.at(1), '20.00');
    await tester.enterText(fields.at(2), passphrase);
    await tester.enterText(fields.at(3), passphrase);
    await settle(tester);
    // "New members need approval" switch is the only YaruSwitchListTile here.
    await tester.tap(find.byType(YaruSwitchListTile).first);
    await settle(tester);
    await tester.tap(filled('Create group'));
    await settle(tester, 12); // PBKDF2 on a background isolate

    final groupService = GroupService();
    final groups = await groupService.getAllGroups();
    final group = groups.where((g) => g.name == groupName).single;
    expect(group.requireApproval, isTrue);
    File('${dir.path}/group.txt').writeAsStringSync(group.id);
    File('${dir.path}/name.txt').writeAsStringSync(groupName);

    // --- open it and create an invite -----------------------------------------
    await tester.tap(find.text(groupName).first);
    await settle(tester, 4);
    await tester.tap(find.byTooltip('Invite members'));
    // Publishes the snapshot to IPFS first; give the network up to 40 s.
    final linkWidget = find.byType(SelectableText);
    for (var i = 0; i < 20 && linkWidget.evaluate().isEmpty; i++) {
      await settle(tester, 2);
    }
    expect(linkWidget, findsOneWidget, reason: 'invite dialog shows the link');
    final link = (tester.widget(linkWidget) as SelectableText).data!;
    expect(link, startsWith('vbank://join'));
    File('${dir.path}/invite.txt').writeAsStringSync(link);
    await tester.tap(filled('Done'));
    await settle(tester);
    stage('invited');

    // --- wait for the phone's join request to arrive over pubsub --------------
    final pending = await waitFor<Member>(
      tester,
      () async {
        final g = await groupService.getGroup(group.id);
        return g?.members.where((m) => m.status == MemberStatus.pending).firstOrNull;
      },
      const Duration(minutes: 5),
      'the phone\'s join request',
    );
    expect(pending, isNotNull, reason: 'phone member should appear as pending');
    stage('joined');
    final phone = pending!;

    // --- approve from the Members tab ------------------------------------------
    // Applying the join republishes the snapshot and refreshes the group list;
    // the detail page can be mid-rebuild (or lose its selection) at that moment.
    for (var i = 0; i < 10 && find.byType(TabBar).evaluate().isEmpty; i++) {
      await settle(tester, 2);
      if (find.byType(TabBar).evaluate().isEmpty && find.text(groupName).evaluate().isNotEmpty) {
        await tester.tap(find.text(groupName).first);
        await settle(tester, 2);
      }
    }
    await tester.tap(tab('Members'));
    await settle(tester, 3);
    // The roster refreshes when the sync change lands; give it up to 30 s and
    // nudge it by re-entering the tab if it is slow.
    final menus = find.byType(PopupMenuButton<String>);
    for (var i = 0; i < 10 && menus.evaluate().isEmpty; i++) {
      await tester.tap(tab('Overview'));
      await settle(tester, 1);
      await tester.tap(tab('Members'));
      await settle(tester, 2);
    }
    expect(menus, findsWidgets, reason: 'pending member has an actions menu');
    await tester.tap(menus.first);
    await settle(tester);
    await tester.tap(find.text('Approve join request'));
    await settle(tester, 6);
    final approved = await groupService.getGroup(group.id);
    expect(
      approved!.members.where((m) => m.peerId == phone.peerId).single.status,
      MemberStatus.active,
    );
    stage('approved');
    await settle(tester, 20); // let the snapshot reach the phone

    // --- record three contributions for the phone member ------------------------
    // The default loan terms require three contributions before a loan.
    await tester.tap(tab('Overview'));
    await settle(tester, 2);
    for (var i = 0; i < 3; i++) {
      await tester.tap(filled('Record transaction'));
      await settle(tester, 2);
      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await settle(tester);
      await tester.tap(find.text(phone.name).last);
      await settle(tester);
      await tester.tap(filled('Record'));
      await settle(tester, 6);
    }
    final txs = await TransactionService().getByGroupId(group.id);
    expect(txs.where((t) => t.fromPeerId == phone.peerId).length, 3);
    stage('contributed');

    // --- wait for the phone to request a loan ----------------------------------
    final loanService = LoanService(groupService: groupService, transactionService: TransactionService());
    final loan = await waitFor<LoanRequest>(
      tester,
      () async => (await loanService.getByGroupId(group.id))
          .where((l) => l.borrowerPeerId == phone.peerId && l.status == LoanStatus.pending)
          .firstOrNull,
      const Duration(minutes: 5),
      'a loan request from the phone',
    );
    expect(loan, isNotNull, reason: 'phone\'s loan request should arrive');
    stage('loan-requested');

    // --- approve, disburse, record one repayment (loan detail page) ------------
    await tester.tap(tab('Loans'));
    await settle(tester, 3);
    await tester.tap(find.textContaining(phone.name).first);
    await settle(tester, 3);
    await tester.tap(filled('Approve'));
    await settle(tester, 2);
    await tester.tap(filled('Approve').last);
    await settle(tester, 3);
    await waitGone(tester, find.textContaining('Loan approved'));
    await tester.tap(filled('Record disbursement'));
    await settle(tester, 4);
    await waitGone(tester, find.textContaining('Loan disbursed'));
    await tester.tap(filled('Record repayment'));
    await settle(tester, 2);
    await tester.tap(filled('Record').last);
    await settle(tester, 6);
    final after = (await loanService.getByGroupId(group.id)).where((l) => l.id == loan!.id).single;
    expect(after.status, anyOf(LoanStatus.repaying, LoanStatus.disbursed, LoanStatus.completed));
    stage('loan-done');
    await tester.pageBack();
    await settle(tester, 3);

    // --- schedule a meeting (Material date + time pickers under Yaru) ---------
    await tester.tap(tab('Meetings'));
    await settle(tester, 2);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Schedule meeting'));
    await settle(tester, 2);
    await tester.tap(find.text('OK'));
    await settle(tester, 2);
    await tester.tap(find.text('OK'));
    await settle(tester, 6);
    final meetings = await MeetingService().getByGroupId(group.id);
    expect(meetings, isNotEmpty);
    stage('meeting');

    // Give the phone time to pull everything, then summarise.
    await settle(tester, 30);
    final finalGroup = await groupService.getGroup(group.id);
    final summary = {
      'group': groupName,
      'members': finalGroup!.members.map((m) => '${m.name}:${m.role.name}:${m.status.name}').toList(),
      'transactions': (await TransactionService().getByGroupId(group.id))
          .map((t) => '${t.type.name} ${t.amount} ${t.status.name}')
          .toList(),
      'loans': (await loanService.getByGroupId(group.id)).map((l) => '${l.requestedAmount} ${l.status.name}').toList(),
      'meetings': meetings.map((m) => '${m.scheduledAt.toIso8601String()} ${m.status.name}').toList(),
    };
    File('${dir.path}/summary.json').writeAsStringSync(const JsonEncoder.withIndent('  ').convert(summary));
    stage('done');
  }, timeout: const Timeout(Duration(minutes: 25)));
}
