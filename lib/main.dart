import 'dart:io';


import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'ui/ui.dart' show VBankTheme, pushScreen, showMessage;
import 'core/ipfs/sync_manager.dart' show SyncChangeType;
import 'providers/group_provider.dart' show selectedGroupProvider;
import 'services/group_service.dart';
import 'services/transaction_service.dart';
import 'screens/loan/loan_detail_screen.dart';
import 'screens/meeting/meeting_detail_screen.dart';
import 'screens/transaction/transaction_detail_screen.dart';
import 'core/app_bootstrap.dart';
import 'core/app_platform.dart';
import 'core/deeplink/deeplink_handler.dart';
import 'desktop/linux/yaru_app.dart';
import 'desktop/macos/macos_app.dart';
import 'desktop/windows/fluent_app.dart';
import 'core/ipfs/ipfs_service.dart';
import 'core/notifications/notification_service.dart';

import 'screens/onboarding/welcome_screen.dart';
import 'screens/onboarding/create_account_screen.dart';
import 'screens/onboarding/restore_backup_screen.dart';
import 'screens/home/home_screen.dart';
import 'screens/group/create_group_screen.dart';
import 'screens/group/group_detail_screen.dart';
import 'screens/transaction/transaction_list_screen.dart';
import 'screens/transaction/create_transaction_screen.dart';
import 'screens/loan/loan_list_screen.dart';
import 'screens/loan/request_loan_screen.dart';
import 'screens/meeting/meeting_list_screen.dart';
import 'screens/invite/join_group_screen.dart';
import 'screens/invite/invite_screen.dart';
import 'screens/group/group_settings_screen.dart';
import 'screens/group/group_reports_screen.dart';
import 'screens/settings/sync_status_screen.dart';
import 'screens/settings/notification_settings_screen.dart';
import 'screens/settings/identity_backup_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Must precede any dart_ipfs usage (see IpfsService.prepareWorkingDirectory).
  await IpfsService.prepareWorkingDirectory();
  // flutter_local_notifications has no Windows backend in this version.
  if (AppPlatform.canNotify) await NotificationService().initialize();

  runApp(const ProviderScope(child: VBankRoot()));
}

/// Picks the presentation for the host platform: shadcn_flutter on phones and
/// each desktop's own design system — Yaru on Linux, macos_ui on macOS, Fluent
/// on Windows (DESIGN_PLAN §37). Everything below the shell — services,
/// providers, crypto, storage, sync — is shared.
class VBankRoot extends StatelessWidget {
  const VBankRoot({super.key});

  @override
  Widget build(BuildContext context) => switch (AppPlatform.shell) {
        AppShell.mobile => const VBankApp(),
        AppShell.linux => const VBankYaruApp(),
        AppShell.macos => const VBankMacosApp(),
        AppShell.windows => const VBankFluentApp(),
      };
}

/// Every route gets its own sheet layer so `showAppSheet`/`confirmSheet`
/// can be opened from a screen's own context and the Android back button
/// closes the sheet (not the screen) — shadcn's Scaffold only provides one
/// below itself, which screen-level contexts can't see.
MapEntry<String, WidgetBuilder> _withSheetLayer(String name, WidgetBuilder builder) =>
    MapEntry(name, (context) => DrawerOverlay(child: builder(context)));

class VBankApp extends ConsumerStatefulWidget {
  const VBankApp({super.key});

  @override
  ConsumerState<VBankApp> createState() => _VBankAppState();
}

class _VBankAppState extends ConsumerState<VBankApp> {

  /// The widget's own context sits *above* the MaterialApp's Navigator, so
  /// deep-link navigation must go through this key instead.
  final _navigatorKey = GlobalKey<NavigatorState>();

  /// Opens the record a notification is about: the group first (screens read
  /// `selectedGroupProvider`), then the transaction, loan or meeting.
  Future<void> _onNotificationTap(NotificationTarget target) async {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _onNotificationTap(target));
      return;
    }
    final group = await GroupService().getGroup(target.groupId);
    if (group == null || !mounted) return;
    ref.read(selectedGroupProvider.notifier).state = group;
    switch (target.type) {
      case SyncChangeType.transaction:
      case SyncChangeType.reversal:
        final tx = target.recordId == null ? null : await TransactionService().getById(target.recordId!);
        if (!mounted) return;
        if (tx != null) {
          navigator.pushNamed('/group-detail');
          pushScreen(navigator.context, TransactionDetailScreen(transaction: tx));
        } else {
          navigator.pushNamed('/group-detail');
        }
      case SyncChangeType.loan:
        navigator.pushNamed('/group-detail');
        if (target.recordId != null) pushScreen(navigator.context, LoanDetailScreen(loanId: target.recordId!));
      case SyncChangeType.meeting:
        navigator.pushNamed('/group-detail');
        if (target.recordId != null) pushScreen(navigator.context, MeetingDetailScreen(meetingId: target.recordId!));
      case SyncChangeType.group:
      case SyncChangeType.member:
        navigator.pushNamed('/group-detail');
    }
  }

  void _onDeepLink(DeepLinkResult result) {
    if (!mounted) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      // Navigator not built yet; retry on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) => _onDeepLink(result));
      return;
    }
    switch (result.type) {
      case DeepLinkType.joinGroup:
        navigator.pushNamed('/join-group', arguments: result);
        break;
      case DeepLinkType.restoreBackup:
        navigator.pushNamed('/restore-backup', arguments: result);
        break;
      case DeepLinkType.error:
        showMessage(navigator.context, result.error ?? 'Invalid link', error: true);
        break;
      case DeepLinkType.unknown:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppBootstrap(
      onDeepLink: _onDeepLink,
      onNotificationTap: _onNotificationTap,
      child: VBankTheme.componentThemes(
      child: ShadcnApp(
      navigatorKey: _navigatorKey,
      title: 'vBank',
      debugShowCheckedModeBanner: false,
      theme: VBankTheme.light(),
      darkTheme: VBankTheme.dark(),
      themeMode: ThemeMode.system,
      // Matches Material's page-transition backdrop and the status-bar icons to
      // the live theme (see VBankTheme.pageTransitionShim).
      builder: (context, child) => VBankTheme.pageTransitionShim(context, child ?? const SizedBox.shrink()),
      initialRoute: '/',
      routes: {
        '/': (context) => const _BackgroundOnBack(child: WelcomeScreen()),
        '/create-account': (context) => const CreateAccountScreen(),
        '/restore-backup': (context) => RestoreBackupScreen(
              backupId: (ModalRoute.of(context)?.settings.arguments as DeepLinkResult?)?.backupId,
            ),
        '/home': (context) => const _BackgroundOnBack(child: HomeScreen()),
        '/create-group': (context) => const CreateGroupScreen(),
        '/group-detail': (context) => const GroupDetailScreen(),
        '/transactions': (context) => const TransactionListScreen(),
        '/create-transaction': (context) => const CreateTransactionScreen(),
        '/loans': (context) => const LoanListScreen(),
        '/request-loan': (context) => const RequestLoanScreen(),
        '/meetings': (context) => const MeetingListScreen(),
        '/join-group': (context) => JoinGroupScreen(
              deepLink:
                  ModalRoute.of(context)?.settings.arguments as DeepLinkResult?,
            ),
        '/invite': (context) => const InviteScreen(),
        '/group-settings': (context) => const GroupSettingsScreen(),
        '/group-reports': (context) => const GroupReportsScreen(),
        '/sync-status': (context) => const SyncStatusScreen(),
        '/notification-settings': (context) => const NotificationSettingsScreen(),
        '/identity-backup': (context) => const IdentityBackupScreen(),
      }.map(_withSheetLayer),
      ),
      ),
    );
  }
}

/// Back on a root route sends the app to the background instead of quitting.
///
/// On Android, finishing the activity tears down the Dart root isolate and with
/// it the sync node (a worker isolate) — while the user expects the app to keep
/// syncing like a messenger. `canPop: false` also makes the framework claim the
/// back event, so predictive back does not finish the activity on its own.
class _BackgroundOnBack extends StatelessWidget {
  final Widget child;
  const _BackgroundOnBack({required this.child});

  static const _platform = MethodChannel('vbank/platform');

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) return child;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        try {
          await _platform.invokeMethod<void>('moveToBackground');
        } catch (_) {
          await SystemNavigator.pop();
        }
      },
      child: child,
    );
  }
}
