import '../app/group_service.dart';
import '../app/sync_coordinator.dart';
import '../domain/core/result.dart';
import '../domain/currency.dart';
import '../domain/group.dart';
import '../domain/loans.dart';
import '../domain/meetings.dart';
import '../domain/membership.dart';
import '../domain/repositories.dart';
import '../domain/transactions.dart';
import 'notification_texts.dart';
import 'notifier.dart';

/// The value, or null on failure.
T? _ok<T>(Result<T> result) => result.isOk ? result.value : null;

/// Turns a sync change into a notification: resolves names and amounts,
/// skips our own echoes, shows through [notifier].
Future<void> notifySyncChange(
  SyncChange change, {
  required GroupService groups,
  required TransactionRepository transactions,
  required LoanRepository loans,
  required MeetingRepository meetings,
  required Notifier notifier,
  required String? selfPeerId,
}) async {
  final Group? group = _ok(await groups.getGroup(change.groupId));
  final String groupName = group?.name ?? 'Your group';

  String? memberName;
  String? amount;
  switch (change.type) {
    case SyncChangeType.transaction:
      if (change.recordId == null) {
        return;
      }
      final Transaction? tx =
          _ok(await transactions.findById(change.recordId!));
      if (tx == null) {
        return;
      }
      if (tx.authorPeerId == selfPeerId) {
        return;
      }
      memberName = await _memberName(groups, change.groupId, tx.authorPeerId);
      final String money =
          CurrencyConfig.supported[tx.currency]?.format(tx.amount) ??
          '${tx.amount} ${tx.currency}';
      amount = '${_verbFor(tx.type)} $money';
    case SyncChangeType.member:
      if (change.recordId == null || change.recordId == selfPeerId) {
        return;
      }
      memberName = await _memberName(groups, change.groupId, change.recordId!);
    case SyncChangeType.loan:
      if (change.recordId == null) {
        return;
      }
      final LoanRequest? loan =
          _ok(await loans.findById(change.recordId!));
      if (loan == null) {
        return;
      }
      if (loan.borrowerPeerId == selfPeerId &&
          loan.status == LoanStatus.pending) {
        return;
      }
      memberName = await _memberName(
        groups,
        change.groupId,
        loan.borrowerPeerId,
      );
      amount = _loanWords(loan);
    case SyncChangeType.meeting:
      if (change.recordId == null) {
        return;
      }
      final Meeting? meeting =
          _ok(await meetings.findById(change.recordId!));
      if (meeting == null) {
        return;
      }
      amount = 'on ${_dayOf(meeting.scheduledAt)}';
    case SyncChangeType.reversal:
      if (change.recordId == null) {
        return;
      }
      final List<TransactionReversal> reversals = _ok(
            await transactions.reversalsByGroup(change.groupId),
          ) ??
          const [];
      TransactionReversal? reversal;
      for (final TransactionReversal r in reversals) {
        if (r.id == change.recordId) {
          reversal = r;
        }
      }
      if (reversal == null) {
        return;
      }
      if (reversal.requestedByPeerId == selfPeerId) {
        return;
      }
      memberName = await _memberName(
        groups,
        change.groupId,
        reversal.requestedByPeerId,
      );
    case SyncChangeType.group:
      break;
  }
  final NotificationText? text = notificationTextFor(
    change,
    groupName: groupName,
    memberName: memberName,
    amount: amount,
  );
  if (text == null) {
    return;
  }
  await notifier.show(
    id: notificationIdFor(change),
    title: text.title,
    body: text.body,
  );
}

/// Display name for a roster member, falling back to a short peer id.
Future<String?> _memberName(
  GroupService groups,
  String groupId,
  String peerId,
) async {
  final Group? group = _ok(await groups.getGroup(groupId));
  if (group == null) {
    return null;
  }
  for (final Member m in group.members) {
    if (m.peerId == peerId) {
      return m.name;
    }
  }
  return peerId.length <= 8 ? peerId : peerId.substring(0, 8);
}

/// Past-tense verb for a transaction type.
String _verbFor(TransactionType type) => switch (type) {
  TransactionType.contribution => 'contributed',
  TransactionType.loan => 'borrowed',
  TransactionType.repayment => 'repaid',
  TransactionType.withdrawal => 'withdrew',
  TransactionType.fee => 'paid fee',
  TransactionType.penalty => 'paid penalty',
  TransactionType.reversal => 'reversed',
};

/// Short words for a loan state change.
String _loanWords(LoanRequest loan) => switch (loan.status) {
  LoanStatus.pending => 'requested a loan',
  LoanStatus.approved => 'got a loan approved',
  LoanStatus.rejected => 'had a loan rejected',
  LoanStatus.disbursed => 'received a loan',
  LoanStatus.repaying => 'is repaying',
  LoanStatus.completed => 'cleared a loan',
  LoanStatus.defaulted => 'defaulted',
};

/// Short day for a meeting date.
String _dayOf(DateTime at) {
  const List<String> days = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];
  return days[(at.weekday - 1) % 7];
}
