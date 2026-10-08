import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/widgets.dart';

import '../app/governance_service.dart';
import '../app/group_service.dart';
import '../app/sync_coordinator.dart';
import 'providers/sync.dart';
import '../app/invite_service.dart';
import '../app/key_service.dart';
import '../app/loan_service.dart';
import '../app/meeting_service.dart';
import '../app/report_service.dart';
import '../app/transaction_service.dart';
import '../domain/repositories.dart';

/// Every repository the presentation layer reads. Assembled once at
/// startup from the opened database; tests build it over in-memory
/// repositories instead.
final class AppRepositories {
  /// Groups and members.
  final GroupRepository groups;

  /// Transactions and reversals.
  final TransactionRepository transactions;

  /// Loans and schedules.
  final LoanRepository loans;

  /// Meetings and attendance.
  final MeetingRepository meetings;

  /// Invites.
  final InviteRepository invites;

  /// Removals, transfers, dissolutions.
  final GovernanceRepository governance;

  /// Backups and identity.
  final BackupRepository backups;

  /// Balance snapshots.
  final BalanceRepository balances;

  /// Opaque settings.
  final SettingsRepository settings;

  /// Creates the repository set.
  const AppRepositories({
    required this.groups,
    required this.transactions,
    required this.loans,
    required this.meetings,
    required this.invites,
    required this.governance,
    required this.backups,
    required this.balances,
    required this.settings,
  });
}

/// Every application service, wired to [AppRepositories] plus the device
/// signer, clock and ids. Screens never touch repositories directly.
final class AppServices {
  /// Roster and governance records.
  final GroupService groups;

  /// Money movements.
  final TransactionService transactions;

  /// Loan lifecycle.
  final LoanService loans;

  /// Meetings.
  final MeetingService meetings;

  /// Invites.
  final InviteService invites;

  /// Corrections and dissolution.
  final GovernanceService governance;

  /// Group keys.
  final GroupKeyService keys;

  /// Statements.
  final ReportService reports;

  /// Creates the service set.
  const AppServices({
    required this.groups,
    required this.transactions,
    required this.loans,
    required this.meetings,
    required this.invites,
    required this.governance,
    required this.keys,
    required this.reports,
  });
}

/// The assembled dependencies. Overridden at the root by the platform
/// startup (real database) and in widget tests (in-memory repositories).
final appRepositoriesProvider = Provider<AppRepositories>(
  (ref) => throw UnimplementedError('AppRepositories not assembled'),
);

/// The assembled services. Overridden alongside [appRepositoriesProvider].
final appServicesProvider = Provider<AppServices>(
  (ref) => throw UnimplementedError('AppServices not assembled'),
);

/// Runs [child] with [repositories] and [services] installed.
final class VBankScope extends StatelessWidget {
  /// Repository set (real or in-memory).
  final AppRepositories repositories;

  /// Service set wired to [repositories].
  final AppServices services;

  /// Sync coordinator, or null where no node runs (widget tests).
  final SyncCoordinator? coordinator;

  /// Extra overrides for tests (pinned clocks and the like).
  final List<Override> extraOverrides;

  /// The app below.
  final Widget child;

  /// Creates the scope.
  const VBankScope({
    super.key,
    required this.repositories,
    required this.services,
    required this.child,
    this.coordinator,
    this.extraOverrides = const [],
  });

  @override
  Widget build(BuildContext context) => ProviderScope(
        overrides: [
          appRepositoriesProvider.overrideWithValue(repositories),
          appServicesProvider.overrideWithValue(services),
          syncCoordinatorProvider.overrideWithValue(coordinator),
          ...extraOverrides,
        ],
        child: child,
      );
}
