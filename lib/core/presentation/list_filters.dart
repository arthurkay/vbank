/// Platform-neutral list plumbing: formatting, search haystacks and filter
/// definitions shared by all four UI shells (shadcn on mobile, Yaru on Linux,
/// macos_ui on macOS, Fluent on Windows). Nothing here imports a widget
/// library, so each shell renders it with its own controls.
library;

import '../../models/group.dart';
import '../../models/loan.dart';
import '../../models/meeting.dart';
import '../../models/transaction.dart';

/// A named predicate — rendered as a chip, a segmented control, a pull-down or
/// a combo box depending on the platform.
class ListFilter<T> {
  final String label;
  final bool Function(T) test;
  const ListFilter(this.label, this.test);

  static ListFilter<T> all<T>([String label = 'All']) => ListFilter<T>(label, (_) => true);
}

/// Case-insensitive substring match used by every search box in the app.
bool matchesQuery(String haystack, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return haystack.toLowerCase().contains(q);
}

// -----------------------------------------------------------------------------
// Formatting
// -----------------------------------------------------------------------------

String fmtDateTime(DateTime d) => d.toLocal().toString().split('.').first.substring(0, 16);
String fmtDate(DateTime d) => d.toLocal().toString().split(' ').first;
String fmtMoney(String currency, double amount) => '$currency ${amount.toStringAsFixed(2)}';

/// `Contribution`, `Loan`, … for display.
String titleCase(String value) =>
    value.isEmpty ? value : '${value[0].toUpperCase()}${value.substring(1)}';

// -----------------------------------------------------------------------------
// Transactions
// -----------------------------------------------------------------------------

String transactionHaystack(Transaction tx, {Group? group}) {
  String nameOf(String peerId) => peerId == 'group'
      ? 'group fund'
      : group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? '';
  return [
    tx.type.name,
    tx.status.name,
    tx.note ?? '',
    tx.currency,
    tx.amount.toStringAsFixed(2),
    fmtDate(tx.timestamp),
    nameOf(tx.fromPeerId),
    nameOf(tx.toPeerId),
    group?.name ?? '',
  ].join(' ');
}

List<ListFilter<Transaction>> transactionFilters() => [
      ListFilter.all<Transaction>(),
      ListFilter('Contributions', (t) => t.type == TransactionType.contribution),
      ListFilter('Loans', (t) => t.type == TransactionType.loan),
      ListFilter('Repayments', (t) => t.type == TransactionType.repayment),
      ListFilter('Penalties', (t) => t.type == TransactionType.penalty),
      ListFilter('Withdrawals', (t) => t.type == TransactionType.withdrawal),
      ListFilter('Reversed',
          (t) => t.status == TransactionStatus.reversed || t.type == TransactionType.reversal),
    ];

// -----------------------------------------------------------------------------
// Members
// -----------------------------------------------------------------------------

String memberHaystack(Member m) => '${m.name} ${m.role.name} ${m.status.name}';

List<ListFilter<Member>> memberFilters() => [
      ListFilter.all<Member>(),
      ListFilter('Admins', (m) => m.role != MemberRole.member),
      ListFilter('Members', (m) => m.role == MemberRole.member),
      ListFilter('Pending', (m) => m.status == MemberStatus.pending),
      ListFilter('Suspended', (m) => m.status == MemberStatus.suspended),
      ListFilter('With loans', (m) => m.hasOutstandingLoan),
    ];

// -----------------------------------------------------------------------------
// Loans
// -----------------------------------------------------------------------------

String loanHaystack(LoanRequest l, {String borrower = ''}) =>
    '$borrower ${l.status.name} ${l.requestedAmount.toStringAsFixed(2)} ${l.termWeeks} weeks ${l.reason ?? ''}';

List<ListFilter<LoanRequest>> loanFilters() => [
      ListFilter.all<LoanRequest>(),
      ListFilter('Pending', (l) => l.status == LoanStatus.pending),
      ListFilter('Active', (l) => l.isActive),
      ListFilter('Completed', (l) => l.status == LoanStatus.completed),
      ListFilter('Rejected', (l) => l.status == LoanStatus.rejected || l.status == LoanStatus.defaulted),
    ];

// -----------------------------------------------------------------------------
// Meetings
// -----------------------------------------------------------------------------

String meetingHaystack(Meeting m, {String group = ''}) =>
    '$group ${fmtDateTime(m.scheduledAt)} ${m.status.name} ${m.notes ?? ''}';

List<ListFilter<Meeting>> meetingFilters() => [
      ListFilter.all<Meeting>(),
      ListFilter('Scheduled', (m) => m.status == MeetingStatus.scheduled),
      ListFilter('Completed', (m) => m.status == MeetingStatus.completed),
      ListFilter('Cancelled', (m) => m.status == MeetingStatus.cancelled),
    ];

// -----------------------------------------------------------------------------
// Groups
// -----------------------------------------------------------------------------

String groupHaystack(Group g) => '${g.name} ${g.status.name} ${g.config.currency}';
