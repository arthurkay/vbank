import 'dart:typed_data';

import 'backup.dart';
import 'balance.dart';
import 'core/result.dart';
import 'governance.dart';
import 'group.dart';
import 'identity.dart';
import 'invites.dart';
import 'loans.dart';
import 'meetings.dart';
import 'transactions.dart';

/// Storage ports. Every method speaks entities and [Result]; SQLite, DTOs
/// and conflict handling live in `lib/src/data`. Services depend only on
/// these, so unit tests swap in fakes without a database.
///
/// Conventions across all repositories:
/// * `find…` returns `Err(NotFoundFailure)` when the record is absent.
/// * `save…` upserts: same id means same content, last write wins — this is
///   what sync convergence needs.
/// * `watch…` replays current state on subscribe, then every change.
/// * `close` releases streams. The database itself is owned by the opener.
abstract interface class GroupRepository {
  /// All groups with their members attached, live.
  Stream<List<Group>> watchGroups();

  /// All groups with their members attached, by name.
  Future<Result<List<Group>>> listAll();

  /// The group with its members, or `Err(NotFoundFailure)`.
  Future<Result<Group>> findById(String id);

  /// Upserts the group, its config and its full member set: members absent
  /// from [group.members] are removed (snapshots are atomic).
  Future<Result<Unit>> save(Group group);

  /// Deletes the group; members, transactions and derived rows cascade.
  Future<Result<Unit>> delete(String id);

  /// Releases streams.
  Future<void> close();
}

/// Transactions and their reversal requests.
abstract interface class TransactionRepository {
  /// Confirmed transactions of a group, oldest first, live.
  Stream<List<Transaction>> watchByGroup(String groupId);

  /// Confirmed transactions of a group, oldest first.
  Future<Result<List<Transaction>>> listByGroup(String groupId);

  /// One transaction, or `Err(NotFoundFailure)`.
  Future<Result<Transaction>> findById(String id);

  /// Upserts a transaction.
  Future<Result<Unit>> save(Transaction transaction);

  /// Flips a transaction to `reversed`. No-op when already reversed.
  Future<Result<Unit>> markReversed(String id);

  /// Upserts a reversal request.
  Future<Result<Unit>> saveReversal(TransactionReversal reversal);

  /// A group's reversal requests, newest first.
  Future<Result<List<TransactionReversal>>> reversalsByGroup(String groupId);

  /// Releases streams.
  Future<void> close();
}

/// Loans and their repayment schedules.
abstract interface class LoanRepository {
  /// A group's loans, newest first, live.
  Stream<List<LoanRequest>> watchByGroup(String groupId);

  /// A group's loans, newest first.
  Future<Result<List<LoanRequest>>> listByGroup(String groupId);

  /// One loan, or `Err(NotFoundFailure)`.
  Future<Result<LoanRequest>> findById(String id);

  /// Upserts a loan.
  Future<Result<Unit>> saveLoan(LoanRequest loan);

  /// Replaces a loan's full schedule (schedules regenerate on approval).
  Future<Result<Unit>> saveSchedules(
    String loanId,
    List<RepaymentSchedule> schedules,
  );

  /// One loan's schedule, instalment order.
  Future<Result<List<RepaymentSchedule>>> schedulesByLoan(String loanId);

  /// Releases streams.
  Future<void> close();
}

/// Meetings and their attendance sheets.
abstract interface class MeetingRepository {
  /// A group's meetings, newest first, live.
  Stream<List<Meeting>> watchByGroup(String groupId);

  /// A group's meetings, newest first.
  Future<Result<List<Meeting>>> listByGroup(String groupId);

  /// One meeting with attendance, or `Err(NotFoundFailure)`.
  Future<Result<Meeting>> findById(String id);

  /// Upserts a meeting and replaces its attendance sheet.
  Future<Result<Unit>> save(Meeting meeting);

  /// Releases streams.
  Future<void> close();
}

/// One-use tickets into groups.
abstract interface class InviteRepository {
  /// A group's invites, newest first, live.
  Stream<List<Invite>> watchByGroup(String groupId);

  /// An invite, or `Err(NotFoundFailure)`.
  Future<Result<Invite>> findById(String id);

  /// A group's invites, newest first.
  Future<Result<List<Invite>>> listByGroup(String groupId);

  /// Upserts an invite.
  Future<Result<Unit>> save(Invite invite);

  /// Marks an invite consumed. Never reverts.
  Future<Result<Unit>> markUsed(String id);

  /// Releases streams.
  Future<void> close();
}

/// Removals, ownership transfers and dissolutions.
abstract interface class GovernanceRepository {
  /// A group's removals, newest first.
  Future<Result<List<MemberRemoval>>> removalsByGroup(String groupId);

  /// Records a removal.
  Future<Result<Unit>> saveRemoval(MemberRemoval removal);

  /// Lifts a ban (sets `lifted`, never deletes the record).
  Future<Result<Unit>> liftRemoval(String id);

  /// A group's ownership transfers, newest first.
  Future<Result<List<OwnershipTransfer>>> transfersByGroup(String groupId);

  /// Records a transfer.
  Future<Result<Unit>> saveTransfer(OwnershipTransfer transfer);

  /// A group's dissolution, or `Err(NotFoundFailure)` when never started.
  Future<Result<GroupDissolution>> dissolutionByGroup(String groupId);

  /// Upserts a dissolution.
  Future<Result<Unit>> saveDissolution(GroupDissolution dissolution);

  /// Releases streams.
  Future<void> close();
}

/// Encrypted backups and this device's identity.
abstract interface class BackupRepository {
  /// All backups, newest first.
  Future<Result<List<AppBackup>>> listBackups();

  /// Stores a backup.
  Future<Result<Unit>> saveBackup(AppBackup backup);

  /// Forgets a backup.
  Future<Result<Unit>> deleteBackup(String id);

  /// This device's identity, or null when not created yet.
  Future<Result<UserIdentity?>> loadIdentity();

  /// Stores (or replaces) this device's identity.
  Future<Result<Unit>> saveIdentity(UserIdentity identity);

  /// Forgets the identity (unregisters the device).
  Future<Result<Unit>> clearIdentity();

  /// Releases streams.
  Future<void> close();
}

/// Cached balance snapshots (recomputed from the log by the app layer).
abstract interface class BalanceRepository {
  /// A group's snapshots, live.
  Stream<List<Balance>> watchByGroup(String groupId);

  /// A group's snapshots.
  Future<Result<List<Balance>>> listByGroup(String groupId);

  /// One snapshot, or `Err(NotFoundFailure)`.
  Future<Result<Balance>> find(String peerId, String groupId);

  /// Replaces a group's whole snapshot set (recomputes are atomic).
  Future<Result<Unit>> saveAll(String groupId, List<Balance> balances);

  /// Releases streams.
  Future<void> close();
}

/// Opaque key-value storage: relay addresses, peer books, sync cursors.
/// Values are bytes; callers encode (JSON, UTF-8) before storing.
abstract interface class SettingsRepository {
  /// Keys starting with [prefix], for enumerating namespaced entries
  /// (e.g. all stored group keys for backup).
  Future<Result<List<String>>> keysWithPrefix(String prefix);

  /// The value for [key], or null when never set.
  Future<Result<Uint8List?>> get(String key);

  /// Stores [value] under [key].
  Future<Result<Unit>> set(String key, Uint8List value);

  /// Forgets [key]. No-op when absent.
  Future<Result<Unit>> remove(String key);

  /// Releases streams.
  Future<void> close();
}
