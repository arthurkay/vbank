import 'dart:async';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import 'core/ipfs/sync_manager.dart' show SyncChange;
import 'providers/auth_provider.dart';
import 'providers/ipfs_provider.dart';
import 'providers/notification_provider.dart';
import 'ui/ui.dart' show VBankTheme, showMessage;
import 'core/deeplink/deeplink_handler.dart';
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
  await NotificationService().initialize();

  runApp(const ProviderScope(child: VBankApp()));
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

class _VBankAppState extends ConsumerState<VBankApp>
    with WidgetsBindingObserver {
  /// The widget's own context sits *above* the MaterialApp's Navigator, so
  /// deep-link navigation must go through this key instead.
  final _navigatorKey = GlobalKey<NavigatorState>();
  final _deepLinkHandler = DeepLinkHandler();
  StreamSubscription<DeepLinkResult>? _deepLinkSub;
  StreamSubscription<SyncChange>? _syncChangesSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initApp();
  }

  Future<void> _initApp() async {
    await ref.read(authProvider.notifier).loadIdentity();

    // The sync manager signs snapshots/invites as us and decides whether to
    // act as an admin, so it needs our identity and key pair.
    await _pushIdentityToSync();
    ref.listenManual(authProvider, (_, _) => _pushIdentityToSync());

    // Surface inbound changes as local notifications (DESIGN_PLAN §20).
    _syncChangesSub = ref.read(syncManagerProvider).changes.listen((change) {
      final title = change.title;
      if (title == null) return;
      ref.read(notificationSchedulerProvider).notifyActivity(
            key: 'activity:${change.type.name}:${DateTime.now().millisecondsSinceEpoch}',
            title: title,
            body: change.body ?? '',
            groupId: change.groupId,
          );
    });

    // Subscribe first: app_links emits the cold-start link on the stream as
    // soon as the handler subscribes, so a listener must already be attached.
    _deepLinkSub = _deepLinkHandler.onDeepLink.listen(_onDeepLink);
    _deepLinkHandler.init();

    // Bring the IPFS node up and start periodic background syncs. Not awaited:
    // node start can take a while and must never block the UI.
    _startNode();
  }

  Future<void> _pushIdentityToSync() async {
    final auth = ref.read(authProvider.notifier);
    final identity = ref.read(authProvider).identity;
    SimpleKeyPair? keyPair;
    if (identity != null && identity.canSign) {
      try {
        keyPair = await auth.requireSigningKeyPair();
      } catch (_) {}
    }
    ref.read(syncManagerProvider).setIdentity(peerId: identity?.peerId, keyPair: keyPair);
  }

  void _startNode() {
    // ignore: discarded_futures
    ref.read(syncManagerProvider).startBackground().catchError((Object e) {
      debugPrint('IPFS background start failed: $e');
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sync = ref.read(syncManagerProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        _startNode(); // idempotent: re-arms the timer and syncs once
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        sync.pauseBackground();
        break;
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
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
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncChangesSub?.cancel();
    _deepLinkSub?.cancel();
    _deepLinkHandler.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return VBankTheme.componentThemes(
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
        '/': (context) => const WelcomeScreen(),
        '/create-account': (context) => const CreateAccountScreen(),
        '/restore-backup': (context) => RestoreBackupScreen(
              backupId: (ModalRoute.of(context)?.settings.arguments as DeepLinkResult?)?.backupId,
            ),
        '/home': (context) => const HomeScreen(),
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
    );
  }
}
