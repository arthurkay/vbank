import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as m;
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
import 'src/presentation/onboarding/onboarding_screen.dart';
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
    final SimpleKeyPair identityKey =
        await SigningService.keyPairFromSeed(secret);
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
      final Signature signature =
          await SigningService.sign(payload, identityKey);
      return Uint8List.fromList(signature.bytes);
    }

    final GroupKeyService keys =
        GroupKeyService(GroupKeyStore(repositories.settings));
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
  Future<void> _push(BuildContext context, Widget screen) => Navigator.push(
        context,
        MaterialPageRoute<void>(builder: (_) => screen),
      );

  /// Joins a group from a share link through the sync coordinator.
  Future<Result<Unit>> _join({
    required String link,
    required String displayName,
  }) => startup.coordinator.joinWithLink(
    link: link,
    displayName: displayName,
  );

  @override
  Widget build(BuildContext context) {
    // Each home sits behind a Builder: pushes need a context below the
    // app's Navigator, and this root context is above it. Without the
    // Builder every Get started tap throws a silent gesture exception.
    if (Platform.isAndroid || Platform.isIOS) {
      return ShadcnApp(
        title: 'vBank',
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => MobileHomeScreen(
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
            builder: (context) => LinuxHomePage(
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
      );
    }
    if (Platform.isMacOS) {
      return MacosApp(
        title: 'vBank',
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => MacosHomePage(
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
      );
    }
    return fluent.FluentApp(
      title: 'vBank',
      debugShowCheckedModeBanner: false,
      home: Builder(
        builder: (context) => WindowsHomePage(
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
    );
  }
}

/// Startup failed before any UI existed.
///
/// Shows a friendly message with the technical details in an expandable
/// section, plus a retry button. The raw error is never shown as the
/// primary message — it goes in the details section instead.
final class _StartupError extends StatelessWidget {
  /// What failed (raw exception text).
  final String error;

  /// Creates the error screen.
  const _StartupError({required this.error});

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
                  Text(
                    _message,
                    textAlign: TextAlign.center,
                  ).muted,
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
                      SelectableText(error).muted.xSmall,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
