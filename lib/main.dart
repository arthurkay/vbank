import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/services.dart';
import 'package:flutter/material.dart' as m;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;
import 'package:macos_ui/macos_ui.dart';
import 'package:path/path.dart' as p;
import 'package:yaru/yaru.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' as ffi;
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'src/app/context.dart';
import 'src/app/device_secret.dart';
import 'src/app/governance_service.dart';
import 'src/app/group_service.dart';
import 'src/app/invite_service.dart';
import 'src/app/key_service.dart';
import 'src/app/loan_service.dart';
import 'src/app/meeting_service.dart';
import 'src/app/report_service.dart';
import 'src/app/sync_coordinator.dart';
import 'src/app/transaction_service.dart';
import 'src/crypto/member_keys.dart';
import 'src/crypto/signing.dart';
import 'src/data/database.dart';
import 'src/data/repositories/backup_repository.dart';
import 'src/data/repositories/balance_repository.dart';
import 'src/notifications/local_notifier.dart';
import 'src/notifications/notifier.dart';
import 'src/notifications/reminder_sink.dart';
import 'src/notifications/sync_notifications.dart';
import 'src/data/repositories/governance_repository.dart';
import 'src/data/repositories/group_repository.dart';
import 'src/data/repositories/invite_repository.dart';
import 'src/data/repositories/loan_repository.dart';
import 'src/data/repositories/meeting_repository.dart';
import 'src/data/repositories/settings_repository.dart';
import 'src/data/repositories/transaction_repository.dart';
import 'src/domain/core/result.dart';
import 'src/presentation/app_scope.dart';
import 'src/presentation/linux/home_page.dart';
import 'src/presentation/linux/onboarding_page.dart';
import 'src/presentation/macos/home_page.dart';
import 'src/presentation/macos/onboarding_page.dart';
import 'src/presentation/mobile/home_screen.dart';
import 'src/presentation/mobile/vbank_theme.dart';
import 'src/presentation/onboarding/onboarding_screen.dart';
import 'src/presentation/sync_on_resume.dart';
import 'src/presentation/windows/onboarding_page.dart';
import 'src/presentation/windows/home_page.dart';
import 'src/sync/ipfs_transport.dart';
import 'src/sync/ledger.dart';
import 'src/sync/peer_book.dart';
import 'src/sync/relay_directory.dart';

/// Starts vBank: device secret, encrypted database, identity keypair, sync
/// node, services, then the platform shell.
///
/// One 32-byte device secret anchors the install: the Ed25519 identity
/// keypair uses it directly, the database password and the X25519 member
/// keypair derive from it with separate HKDF labels. A failure anywhere
/// before the UI shows a plain error screen instead of a half-built app —
/// the failure message names the step so logs stay actionable.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    final _Startup startup = await _Startup.assemble();
    runApp(
      VBankScope(
        repositories: startup.repositories,
        services: startup.services,
        coordinator: startup.coordinator,
        child: _VBankRoot(startup: startup),
      ),
    );
  } catch (e) {
    runApp(_StartupError(error: '$e'));
  }
}

/// Everything the UI needs that only exists after async startup.
final class _Startup {
  /// Assembled repositories.
  final AppRepositories repositories;

  /// Assembled services.
  final AppServices services;

  /// Sync coordinator (node starting best-effort; offline still works).
  final SyncCoordinator coordinator;

  /// This device's Ed25519 public key bytes, for the identity row.
  final Uint8List identityPublicKey;

  /// This device's libp2p peer id, or null when the node could not start.
  final String? Function() peerIdOf;

  /// Builds everything, in order. Throws with the failing step.
  static Future<_Startup> assemble() async {
    final Uint8List secret = await DeviceSecret.get();
    final SimpleKeyPair identityKey = await SigningService.keyPairFromSeed(
      secret,
    );
    final Uint8List identityPublicKey = Uint8List.fromList(
      await SigningService.extractPublicKeyBytes(identityKey),
    );

    final Directory support = await getApplicationSupportDirectory();
    await support.create(recursive: true);
    final String dbPath = p.join(support.path, 'vbank.db');
    final DatabaseFactory factory = _databaseFactory();
    final String dbPassword = await _dbPasswordHex(secret);
    final Result<OpenResult> openedResult = await VBankDatabase.open(
      factory: factory,
      path: dbPath,
      password: dbPassword,
      // Only the desktop FFI builds need the cipher re-selected; real
      // SQLCipher (phones) must not have its provider touched.
      selectCipher: Platform.isLinux || Platform.isWindows,
      // Phones key natively: the plugin applies the key during open.
      // Manual PRAGMA keying cannot reopen an encrypted file there —
      // the native open rejects it before any statement runs. This
      // rebuilds once (old files used the other keying); per-device
      // files never move between platforms, so formats may differ.
      nativePassword: Platform.isAndroid || Platform.isIOS ? dbPassword : null,
    );
    if (openedResult.isErr) {
      throw StateError('database: ${openedResult.failure}');
    }
    final OpenResult opened = openedResult.value;

    final Database db = opened.database;
    final AppRepositories repositories = AppRepositories(
      groups: SqlGroupRepository(db),
      transactions: SqlTransactionRepository(db),
      loans: SqlLoanRepository(db),
      meetings: SqlMeetingRepository(db),
      invites: SqlInviteRepository(db),
      governance: SqlGovernanceRepository(db),
      backups: SqlBackupRepository(db),
      balances: SqlBalanceRepository(db),
      settings: SqlSettingsRepository(db),
    );

    DateTime clock() => DateTime.now().toUtc();
    Future<Uint8List> sign(List<int> payload) async {
      final Signature signature = await SigningService.sign(
        payload,
        identityKey,
      );
      return Uint8List.fromList(signature.bytes);
    }

    final GroupKeyService keys = GroupKeyService(
      GroupKeyStore(repositories.settings),
    );
    final GroupService groups = GroupService(
      groups: repositories.groups,
      governance: repositories.governance,
      loans: repositories.loans,
      keys: keys,
      sign: sign,
      clock: clock,
      ids: uuidV7,
    );
    final TransactionService transactions = TransactionService(
      transactions: repositories.transactions,
      groups: repositories.groups,
      balances: repositories.balances,
      sign: sign,
      clock: clock,
      ids: uuidV7,
    );
    final LoanService loans = LoanService(
      loans: repositories.loans,
      groups: groups,
      transactions: transactions,
      balances: repositories.balances,
      sign: sign,
      clock: clock,
      ids: uuidV7,
    );
    final MeetingService meetings = MeetingService(
      meetings: repositories.meetings,
      groups: groups,
      clock: clock,
      ids: uuidV7,
    );
    final InviteService invites = InviteService(
      invites: repositories.invites,
      sign: sign,
      clock: clock,
      ids: uuidV7,
    );
    final GovernanceService governance = GovernanceService(
      groups: groups,
      transactions: transactions,
      reversals: repositories.transactions,
      governance: repositories.governance,
      loans: repositories.loans,
      balances: repositories.balances,
      sign: sign,
      clock: clock,
      ids: uuidV7,
    );
    final AppServices services = AppServices(
      groups: groups,
      transactions: transactions,
      loans: loans,
      meetings: meetings,
      invites: invites,
      governance: governance,
      keys: keys,
      reports: ReportService(
        transactions: repositories.transactions,
        meetings: repositories.meetings,
        balances: repositories.balances,
        groups: repositories.groups,
      ),
    );

    final IpfsTransport transport = IpfsTransport(
      ipfsDir: p.join(support.path, 'ipfs'),
      identitySeed: secret,
    );
    // Device zone for reminder alarms. Best effort: without it,
    // scheduled reminders fall back to UTC offsets that may be off.
    try {
      tzdata.initializeTimeZones();
      tz.setLocalLocation(
        tz.getLocation(await FlutterTimezone.getLocalTimezone()),
      );
    } catch (_) {}
    final PluginReminderSink reminderSink = PluginReminderSink(
      FlutterLocalNotificationsPlugin(),
    );
    final SyncCoordinator coordinator = SyncCoordinator(
      transport: transport,
      groups: groups,
      transactions: transactions,
      loans: loans,
      meetings: meetings,
      governance: governance,
      invites: invites,
      transactionRepository: repositories.transactions,
      loanRepository: repositories.loans,
      meetingRepository: repositories.meetings,
      keys: keys,
      peers: PeerBook(repositories.settings),
      ledger: SyncLedger(repositories.settings),
      relays: RelayDirectory(),
      settings: repositories.settings,
      sign: sign,
      ownPeerId: () => transport.peerId,
      memberKeyPair: () => MemberKeys.fromIdentitySeed(secret),
      ownAddrs: () => transport.dialableAddresses,
      signingKey: () async => identityKey,
      clock: clock,
      reminders: reminderSink,
    );
    // Best effort: the app works offline, and every round re-runs
    // ensureStarted, so a node that failed here (port busy, no network)
    // heals itself on the next round instead of staying down.
    try {
      await coordinator.ensureStarted();
    } catch (e) {
      debugPrint('vBank: sync node failed to start: $e');
    }
    coordinator.startPeriodic(every: const Duration(minutes: 15));
    // Sync events become system notifications. Best effort throughout:
    // a phone that refuses notifications still syncs and runs.
    final LocalNotifier localNotifier = LocalNotifier();
    await localNotifier.initialize();
    final Notifier notifier = localNotifier;
    coordinator.changes.listen((change) async {
      try {
        await notifySyncChange(
          change,
          groups: groups,
          transactions: repositories.transactions,
          loans: repositories.loans,
          meetings: repositories.meetings,
          notifier: notifier,
          selfPeerId: transport.peerId,
        );
      } catch (e) {
        debugPrint('vBank: notification failed: $e');
      }
    });
    return _Startup._(
      repositories: repositories,
      services: services,
      coordinator: coordinator,
      identityPublicKey: identityPublicKey,
      peerIdOf: () => transport.peerId,
    );
  }

  const _Startup._({
    required this.repositories,
    required this.services,
    required this.coordinator,
    required this.identityPublicKey,
    required this.peerIdOf,
  });

  /// The database factory: FFI on Linux/Windows, the platform plugin
  /// (SQLCipher) everywhere else.
  static DatabaseFactory _databaseFactory() {
    if (Platform.isLinux || Platform.isWindows) {
      ffi.sqfliteFfiInit();
      return ffi.databaseFactoryFfi;
    }
    return databaseFactory;
  }

  /// The SQLCipher key as hex: HKDF of the device secret under a label
  /// that nothing else uses, so the database key and the identity keypair
  /// never coincide.
  static Future<String> _dbPasswordHex(Uint8List secret) async {
    final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
    final SecretKey key = await hkdf.deriveKey(
      secretKey: SecretKey(secret),
      info: 'vbank-db-v1'.codeUnits,
      nonce: List<int>.filled(16, 0),
    );
    final List<int> bytes = await key.extractBytes();
    final StringBuffer hex = StringBuffer();
    for (final int b in bytes) {
      hex.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return hex.toString();
  }
}

/// The platform shell over the signed-in home: shadcn on phones, each
/// desktop's own kit (Yaru, macos_ui, Fluent) everywhere else. Every
/// onboarding screen shares the [saveOnboardingIdentity] contract and
/// reads the peer id fresh on every save, so a node that is still
/// starting (or just healed) works — and a node that is down shows an
/// error with a retry instead of silence.
final class _VBankRoot extends StatelessWidget {
  /// Assembled startup (identity bytes for onboarding).
  final _Startup startup;

  /// Creates the root.
  const _VBankRoot({required this.startup});

  /// Pushes a screen on the nearest navigator.
  Future<void> _push(BuildContext context, Widget screen) =>
      Navigator.push(context, MaterialPageRoute<void>(builder: (_) => screen));

  /// Joins a group from a share link through the sync coordinator.
  Future<Result<Unit>> _join({
    required String link,
    required String displayName,
  }) => startup.coordinator.joinWithLink(link: link, displayName: displayName);

  @override
  Widget build(BuildContext context) {
    // Each home sits behind a Builder: pushes need a context below the
    // app's Navigator, and this root context is above it. Without the
    // Builder every Get started tap throws a silent gesture exception.
    if (Platform.isAndroid || Platform.isIOS) {
      return ShadcnApp(
        title: 'vBank',
        debugShowCheckedModeBanner: false,
        theme: VBankTheme.light,
        darkTheme: VBankTheme.dark,
        themeMode: ThemeMode.system,
        home: Builder(
          builder: (context) => _SystemChromeHost(
            child: SyncOnResume(
              child: MobileHomeScreen(
                onCreateIdentity: () => _push(
                  context,
                  OnboardingScreen(
                    peerIdOf: startup.peerIdOf,
                    publicKey: startup.identityPublicKey,
                  ),
                ),
                onJoinGroup: _join,
              ),
            ),
          ),
        ),
      );
    }
    if (Platform.isLinux) {
      return YaruTheme(
        builder: (context, yaru, child) => m.MaterialApp(
          title: 'vBank',
          debugShowCheckedModeBanner: false,
          theme: yaru.theme,
          darkTheme: yaru.darkTheme,
          home: Builder(
            builder: (context) => SyncOnResume(
              child: LinuxHomePage(
                onCreateIdentity: () => _push(
                  context,
                  LinuxOnboardingPage(
                    peerIdOf: startup.peerIdOf,
                    publicKey: startup.identityPublicKey,
                  ),
                ),
                onJoinGroup: _join,
              ),
            ),
          ),
        ),
      );
    }
    if (Platform.isMacOS) {
      return MacosApp(
        title: 'vBank',
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => SyncOnResume(
            child: MacosHomePage(
              onCreateIdentity: () => _push(
                context,
                MacosOnboardingPage(
                  peerIdOf: startup.peerIdOf,
                  publicKey: startup.identityPublicKey,
                ),
              ),
              onJoinGroup: _join,
            ),
          ),
        ),
      );
    }
    return fluent.FluentApp(
      title: 'vBank',
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => SyncOnResume(
          child: WindowsHomePage(
            onCreateIdentity: () => _push(
              context,
              WindowsOnboardingPage(
                peerIdOf: startup.peerIdOf,
                publicKey: startup.identityPublicKey,
              ),
            ),
            onJoinGroup: _join,
          ),
        ),
      ),
    );
  }
}

/// Keeps the Android status and navigation bars readable: light icons
/// on dark theme, dark icons on light theme, following the system.
/// shadcn never sets the overlay style itself, so without this the
/// status icons vanish on light screens. Global (not per route), so
/// every pushed screen inherits it.
final class _SystemChromeHost extends StatefulWidget {
  /// The app below.
  final Widget child;

  /// Creates the host.
  const _SystemChromeHost({required this.child});

  @override
  State<_SystemChromeHost> createState() => _SystemChromeHostState();
}

final class _SystemChromeHostState extends State<_SystemChromeHost>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Inherited widgets (MediaQuery) are only readable here, not in
    // initState. Runs on first build and on dependency changes.
    _apply();
  }

  @override
  void didChangePlatformBrightness() => _apply();

  /// Applies the overlay matching the current system brightness.
  void _apply() {
    final Brightness brightness = MediaQuery.platformBrightnessOf(context);
    SystemChrome.setSystemUIOverlayStyle(
      brightness == Brightness.dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    );
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Startup failed before any UI existed.
///
/// Shows a friendly message with the technical details in an expandable
/// section, plus a retry button. The raw error is never shown as the
/// primary message — it goes in the details section instead, with the
/// database key redacted (SQL failures echo their statement).
final class _StartupError extends StatelessWidget {
  /// What failed (raw exception text).
  final String error;

  /// Creates the error screen.
  const _StartupError({required this.error});

  /// The error with any hex key material redacted.
  String get safeError =>
      error.replaceAll(RegExp("x'[0-9a-fA-F]{32,}'"), "x'***'");

  /// User-friendly title based on the error type.
  String get _title => error.contains('database')
      ? 'Could not open your database'
      : error.contains('SQLCipher')
      ? 'Encryption unavailable'
      : 'vBank could not start';

  /// User-friendly message based on the error type.
  String get _message => error.contains('database')
      ? 'Your local data store could not be opened. This usually means '
            'the database file is corrupted or the encryption key is wrong. '
            'Your data is safe — it can be restored from other group '
            'members once sync runs.'
      : error.contains('SQLCipher')
      ? 'This device cannot encrypt local data. On Android this means '
            'the app was built without SQLCipher. Please reinstall '
            'the app.'
      : 'Something went wrong while starting vBank. Please try again. '
            'If the problem persists, restart the app.';

  @override
  Widget build(BuildContext context) => ShadcnApp(
    theme: VBankTheme.light,
    darkTheme: VBankTheme.dark,
    themeMode: ThemeMode.system,
    home: Scaffold(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                LucideIcons.triangleAlert,
                size: 48,
                color: Colors.orange,
              ),
              const Gap(16),
              Text(_title).xLarge.bold,
              const Gap(12),
              Text(_message, textAlign: TextAlign.center).muted,
              const Gap(24),
              PrimaryButton(
                onPressed: () {
                  // Re-run main() — the OS keeps the process alive.
                  main();
                },
                child: const Text('Retry'),
              ),
              const Gap(16),
              Collapsible(
                children: [
                  const Text('Technical details').small,
                  const Gap(8),
                  SelectableText(safeError).muted.xSmall,
                ],
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
