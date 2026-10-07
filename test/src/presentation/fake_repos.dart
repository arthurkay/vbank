import 'dart:async';
import 'dart:typed_data';

import 'package:vbank/src/domain/backup.dart';
import 'package:vbank/src/domain/balance.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/core/result.dart';
import 'package:vbank/src/domain/governance.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/identity.dart';
import 'package:vbank/src/domain/invites.dart';
import 'package:vbank/src/domain/loans.dart';
import 'package:vbank/src/domain/meetings.dart';
import 'package:vbank/src/domain/repositories.dart';
import 'package:vbank/src/domain/transactions.dart';

/// In-memory repositories for widget tests: no sqlite, no isolates, so
/// everything resolves in fake-async time with plain `pump()`.
///
/// Watch streams replay current state, then every change. Cancel-safe by
/// construction (explicit controllers, not `await for`).
abstract base class _MemoryRepo {
  final StreamController<void> _changes = StreamController<void>.broadcast();

  /// Wakes every watch stream.
  void notify() {
    if (!_changes.isClosed) {
      _changes.add(null);
    }
  }

  /// Replays [query] now, then after every [notify].
  Stream<List<T>> watch<T>(FutureOr<List<T>> Function() query) {
    StreamController<List<T>>? controller;
    StreamSubscription<void>? subscription;
    Future<void> emit() async {
      final StreamController<List<T>>? target = controller;
      if (target == null || target.isClosed) {
        return;
      }
      try {
        target.add(await query());
      } catch (e, s) {
        if (!target.isClosed) {
          target.addError(e, s);
        }
      }
    }

    controller = StreamController<List<T>>(
      onListen: () {
        subscription = _changes.stream.listen((_) => emit());
        emit();
      },
      onCancel: () => subscription?.cancel(),
    );
    return controller.stream;
  }

  /// Releases streams.
  Future<void> close() => _changes.close();
}

/// In-memory groups and members.
final class MemoryGroupRepository extends _MemoryRepo
    implements GroupRepository {
  /// Stored groups by id.
  final Map<String, Group> groups = {};

  @override
  Stream<List<Group>> watchGroups() => watch(() async => _ordered());

  @override
  Future<Result<List<Group>>> listAll() async => Ok(_ordered());

  @override
  Future<Result<Group>> findById(String id) async {
    final Group? group = groups[id];
    if (group == null) {
      return Err(NotFoundFailure('group:$id'));
    }
    return Ok(group);
  }

  @override
  Future<Result<Unit>> save(Group group) async {
    groups[group.id] = group;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> delete(String id) async {
    groups.remove(id);
    notify();
    return const Ok(unit);
  }

  List<Group> _ordered() {
    final List<Group> all = groups.values.toList()
      ..sort((Group a, Group b) => a.name.compareTo(b.name));
    return all;
  }
}

/// In-memory transactions and reversals.
final class MemoryTransactionRepository extends _MemoryRepo
    implements TransactionRepository {
  /// Stored transactions by id.
  final Map<String, Transaction> transactions = {};

  /// Stored reversals by id.
  final Map<String, TransactionReversal> reversals = {};

  @override
  Stream<List<Transaction>> watchByGroup(String groupId) =>
      watch(() async => _ordered(groupId));

  @override
  Future<Result<List<Transaction>>> listByGroup(String groupId) async =>
      Ok(_ordered(groupId));

  @override
  Future<Result<Transaction>> findById(String id) async {
    final Transaction? tx = transactions[id];
    if (tx == null) {
      return Err(NotFoundFailure('transaction:$id'));
    }
    return Ok(tx);
  }

  @override
  Future<Result<Unit>> save(Transaction transaction) async {
    transactions[transaction.id] = transaction;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> markReversed(String id) async {
    final Transaction? tx = transactions[id];
    if (tx != null) {
      transactions[id] = tx.copyWith(status: TransactionStatus.reversed);
      notify();
    }
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> saveReversal(TransactionReversal reversal) async {
    reversals[reversal.id] = reversal;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<List<TransactionReversal>>> reversalsByGroup(
    String groupId,
  ) async =>
      Ok([
        for (final TransactionReversal r in reversals.values)
          if (r.groupId == groupId) r,
      ]);

  List<Transaction> _ordered(String groupId) {
    final List<Transaction> all = [
      for (final Transaction t in transactions.values)
        if (t.groupId == groupId) t,
    ]..sort(
        (Transaction a, Transaction b) =>
            a.sequenceNumber.compareTo(b.sequenceNumber),
      );
    return all;
  }
}

/// In-memory loans and schedules.
final class MemoryLoanRepository extends _MemoryRepo
    implements LoanRepository {
  /// Stored loans by id.
  final Map<String, LoanRequest> loans = {};

  /// Stored schedules by loan id.
  final Map<String, List<RepaymentSchedule>> schedules = {};

  @override
  Stream<List<LoanRequest>> watchByGroup(String groupId) =>
      watch(() async => _ordered(groupId));

  @override
  Future<Result<List<LoanRequest>>> listByGroup(String groupId) async =>
      Ok(_ordered(groupId));

  @override
  Future<Result<LoanRequest>> findById(String id) async {
    final LoanRequest? loan = loans[id];
    if (loan == null) {
      return Err(NotFoundFailure('loan:$id'));
    }
    return Ok(loan);
  }

  @override
  Future<Result<Unit>> saveLoan(LoanRequest loan) async {
    loans[loan.id] = loan;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> saveSchedules(
    String loanId,
    List<RepaymentSchedule> updated,
  ) async {
    schedules[loanId] = [...updated];
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<List<RepaymentSchedule>>> schedulesByLoan(
    String loanId,
  ) async =>
      Ok([...schedules[loanId] ?? const []]);

  List<LoanRequest> _ordered(String groupId) {
    final List<LoanRequest> all = [
      for (final LoanRequest l in loans.values)
        if (l.groupId == groupId) l,
    ]..sort(
        (LoanRequest a, LoanRequest b) =>
            b.requestedAt.compareTo(a.requestedAt),
      );
    return all;
  }
}

/// In-memory meetings and attendance.
final class MemoryMeetingRepository extends _MemoryRepo
    implements MeetingRepository {
  /// Stored meetings by id.
  final Map<String, Meeting> meetings = {};

  @override
  Stream<List<Meeting>> watchByGroup(String groupId) =>
      watch(() async => _ordered(groupId));

  @override
  Future<Result<List<Meeting>>> listByGroup(String groupId) async =>
      Ok(_ordered(groupId));

  @override
  Future<Result<Meeting>> findById(String id) async {
    final Meeting? meeting = meetings[id];
    if (meeting == null) {
      return Err(NotFoundFailure('meeting:$id'));
    }
    return Ok(meeting);
  }

  @override
  Future<Result<Unit>> save(Meeting meeting) async {
    meetings[meeting.id] = meeting;
    notify();
    return const Ok(unit);
  }

  List<Meeting> _ordered(String groupId) {
    final List<Meeting> all = [
      for (final Meeting m in meetings.values)
        if (m.groupId == groupId) m,
    ]..sort((Meeting a, Meeting b) => b.scheduledAt.compareTo(a.scheduledAt));
    return all;
  }
}

/// In-memory invites.
final class MemoryInviteRepository extends _MemoryRepo
    implements InviteRepository {
  /// Stored invites by id.
  final Map<String, Invite> invites = {};

  @override
  Future<Result<Invite>> findById(String id) async {
    final Invite? invite = invites[id];
    if (invite == null) {
      return Err(NotFoundFailure('invite:$id'));
    }
    return Ok(invite);
  }

  @override
  Future<Result<List<Invite>>> listByGroup(String groupId) async => Ok([
        for (final Invite i in invites.values)
          if (i.groupId == groupId) i,
      ]);

  @override
  Future<Result<Unit>> save(Invite invite) async {
    invites[invite.id] = invite;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> markUsed(String id) async {
    final Invite? invite = invites[id];
    if (invite != null) {
      invites[id] = invite.copyWith(used: true);
      notify();
    }
    return const Ok(unit);
  }
}

/// In-memory removals, transfers and dissolutions.
final class MemoryGovernanceRepository extends _MemoryRepo
    implements GovernanceRepository {
  /// Stored removals by id.
  final Map<String, MemberRemoval> removals = {};

  /// Stored transfers by id.
  final Map<String, OwnershipTransfer> transfers = {};

  /// Stored dissolutions by id.
  final Map<String, GroupDissolution> dissolutions = {};

  @override
  Future<Result<List<MemberRemoval>>> removalsByGroup(String groupId) async =>
      Ok([
        for (final MemberRemoval r in removals.values)
          if (r.groupId == groupId) r,
      ]);

  @override
  Future<Result<Unit>> saveRemoval(MemberRemoval removal) async {
    removals[removal.id] = removal;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> liftRemoval(String id) async {
    final MemberRemoval? removal = removals[id];
    if (removal != null) {
      removals[id] = removal.copyWith(lifted: true);
      notify();
    }
    return const Ok(unit);
  }

  @override
  Future<Result<List<OwnershipTransfer>>> transfersByGroup(
    String groupId,
  ) async =>
      Ok([
        for (final OwnershipTransfer t in transfers.values)
          if (t.groupId == groupId) t,
      ]);

  @override
  Future<Result<Unit>> saveTransfer(OwnershipTransfer transfer) async {
    transfers[transfer.id] = transfer;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<GroupDissolution>> dissolutionByGroup(String groupId) async {
    for (final GroupDissolution d in dissolutions.values) {
      if (d.groupId == groupId) {
        return Ok(d);
      }
    }
    return Err(NotFoundFailure('dissolution:$groupId'));
  }

  @override
  Future<Result<Unit>> saveDissolution(GroupDissolution dissolution) async {
    dissolutions[dissolution.id] = dissolution;
    notify();
    return const Ok(unit);
  }
}

/// In-memory backups and identity.
final class MemoryBackupRepository extends _MemoryRepo
    implements BackupRepository {
  /// Stored backups by id.
  final Map<String, AppBackup> backups = {};

  /// This device's identity, if any.
  UserIdentity? identity;

  @override
  Future<Result<List<AppBackup>>> listBackups() async =>
      Ok(backups.values.toList());

  @override
  Future<Result<Unit>> saveBackup(AppBackup backup) async {
    backups[backup.id] = backup;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> deleteBackup(String id) async {
    backups.remove(id);
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<UserIdentity?>> loadIdentity() async => Ok(identity);

  @override
  Future<Result<Unit>> saveIdentity(UserIdentity value) async {
    identity = value;
    notify();
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> clearIdentity() async {
    identity = null;
    notify();
    return const Ok(unit);
  }
}

/// In-memory balance snapshots.
final class MemoryBalanceRepository extends _MemoryRepo
    implements BalanceRepository {
  /// Stored snapshots by `groupId/peerId`.
  final Map<String, Balance> balances = {};

  @override
  Stream<List<Balance>> watchByGroup(String groupId) =>
      watch(() async => _ordered(groupId));

  @override
  Future<Result<List<Balance>>> listByGroup(String groupId) async =>
      Ok(_ordered(groupId));

  @override
  Future<Result<Balance>> find(String peerId, String groupId) async {
    final Balance? balance = balances['$groupId/$peerId'];
    if (balance == null) {
      return Err(NotFoundFailure('balance:$groupId:$peerId'));
    }
    return Ok(balance);
  }

  @override
  Future<Result<Unit>> saveAll(String groupId, List<Balance> updated) async {
    balances.removeWhere((String key, _) => key.startsWith('$groupId/'));
    for (final Balance b in updated) {
      balances['${b.groupId}/${b.peerId}'] = b;
    }
    notify();
    return const Ok(unit);
  }

  List<Balance> _ordered(String groupId) {
    final List<Balance> all = [
      for (final MapEntry<String, Balance> e in balances.entries)
        if (e.value.groupId == groupId) e.value,
    ]..sort((Balance a, Balance b) => b.netBalance.compareTo(a.netBalance));
    return all;
  }
}

/// In-memory settings.
final class MemorySettingsRepository implements SettingsRepository {
  /// Stored values by key.
  final Map<String, Uint8List> store = {};

  @override
  Future<Result<List<String>>> keysWithPrefix(String prefix) async => Ok([
        for (final String key in store.keys)
          if (key.startsWith(prefix)) key,
      ]);

  @override
  Future<Result<Uint8List?>> get(String key) async => Ok(store[key]);

  @override
  Future<Result<Unit>> set(String key, Uint8List value) async {
    store[key] = value;
    return const Ok(unit);
  }

  @override
  Future<Result<Unit>> remove(String key) async {
    store.remove(key);
    return const Ok(unit);
  }

  @override
  Future<void> close() async {}
}
