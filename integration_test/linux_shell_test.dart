/// Drives the real Linux (Yaru) shell: onboarding → identity → the
/// master-detail shell → creating a group → the group's sections.
///
/// Run with: `flutter test integration_test/linux_shell_test.dart -d linux`
///
/// This exercises the whole desktop stack — the encrypted SQLCipher database
/// through sqflite_common_ffi, the device secret (keyring or file fallback),
/// the shared providers and the Yaru widgets — on the platform it ships to.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vbank/core/storage/database.dart';
import 'package:vbank/core/storage/settings_dao.dart';
import 'package:vbank/main.dart' as app;
import 'package:yaru/yaru.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  /// The IPFS node and periodic sync keep timers alive, so `pumpAndSettle`
  /// would never return; pump a fixed number of frames instead.
  Future<void> settle(WidgetTester tester, [int seconds = 3]) async {
    for (var i = 0; i < seconds * 10; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  testWidgets('onboarding, identity, group creation and sections', (tester) async {
    app.main();
    await settle(tester, 6);

    // 1-2. First run shows the Yaru onboarding page; later runs already have an
    // identity in the desktop database, so only do onboarding when it is there.
    final getStarted = find.widgetWithText(FilledButton, 'Get started');
    if (getStarted.evaluate().isNotEmpty) {
      expect(find.text('vBank'), findsWidgets);
      await tester.tap(getStarted);
      await settle(tester);
      expect(find.byType(YaruDialogTitleBar), findsOneWidget);
      await tester.enterText(find.byType(TextField).first, 'Desktop Tester');
      await settle(tester);
      await tester.tap(find.widgetWithText(FilledButton, 'Get started').last);
      await settle(tester, 5);
    }

    // 3. The shell appears: destinations in the left pane.
    expect(find.text('Groups'), findsWidgets, reason: 'master-detail pane should list destinations');
    expect(find.text('Activity'), findsWidgets);
    expect(find.text('Settings'), findsWidgets);

    // 4. Create a group from the Groups page.
    final groupName = 'Desktop Circle ${DateTime.now().millisecondsSinceEpoch % 100000}';
    final newGroup = find.widgetWithText(FilledButton, 'New group');
    expect(newGroup, findsWidgets);
    await tester.tap(newGroup.first);
    await settle(tester);

    // Scope to the dialog: with 6+ groups the list shows a YaruSearchField too.
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    expect(fields, findsAtLeast(4), reason: 'name, amount, passphrase, confirm');
    await tester.enterText(fields.at(0), groupName);
    await tester.enterText(fields.at(1), '25.00');
    await tester.enterText(fields.at(2), 'correct horse battery staple');
    await tester.enterText(fields.at(3), 'correct horse battery staple');
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
    // Deriving the group key is a deliberate ~1s PBKDF2 on a background isolate.
    await settle(tester, 12);

    // 5. The group is listed, and opening it shows its sections.
    expect(find.text(groupName), findsWidgets, reason: 'new group should appear in the list');
    await tester.tap(find.text(groupName).first);
    await settle(tester, 4);

    // Tab labels render in the bar (and in the Yaru tab indicator), so any
    // occurrence proves the section exists.
    expect(find.text('Overview'), findsWidgets);
    expect(find.text('Transactions'), findsWidgets);
    expect(find.text('Members'), findsWidgets);
    expect(find.text('Loans'), findsWidgets);
    expect(find.text('Meetings'), findsWidgets);
    expect(find.text('Group fund'), findsWidgets, reason: 'overview shows the fund stat');
    expect(find.text('Group rules'), findsWidgets);

    // 6. The database this all went through is a real encrypted file.
    final db = await AppDatabase.getInstance();
    final rows = await db.rawQuery('SELECT count(*) AS n FROM groups');
    expect(rows.first['n'], isNonZero, reason: 'group persisted to the encrypted DB');

    // 7. Sync page: the built-in vBank relay is listed and can be switched off.
    await tester.tap(find.text('Sync').first);
    await settle(tester, 3);
    expect(find.textContaining('vBank relay · vbank.localhost.co.zm'), findsOneWidget);
    expect(find.text('Relay server'), findsWidgets);
    final relaySwitch = find.ancestor(
      of: find.textContaining('vBank relay · vbank.localhost.co.zm'),
      matching: find.byType(YaruSwitchListTile),
    );
    expect(relaySwitch, findsOneWidget);
    expect(tester.widget<YaruSwitchListTile>(relaySwitch).value, isTrue, reason: 'on by default');
    await tester.tap(relaySwitch);
    await settle(tester, 2);
    expect(await SettingsDao().getBool(SettingKeys.builtInRelayEnabled, defaultValue: true), isFalse);
    expect(find.text('Off'), findsWidgets);
    await tester.tap(find.byType(YaruSwitchListTile).first);
    await settle(tester, 2);
    expect(await SettingsDao().getBool(SettingKeys.builtInRelayEnabled, defaultValue: true), isTrue);
  });
}
