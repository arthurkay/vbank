/// Linux shell pages that are not the group browser: cross-group activity and
/// meetings, sync, settings, onboarding, plus the loan and meeting detail
/// pages. Ubuntu idioms throughout — [YaruSection]s of tiles, a
/// [YaruSearchField] over long lists, [YaruSwitchListTile] for preferences.
library;

import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../core/app_platform.dart';
import '../../core/ipfs/sync_manager.dart';
import '../../core/presentation/list_filters.dart';
import '../../core/storage/settings_dao.dart';
import '../../core/storage/transaction_dao.dart' as q;
import '../../models/repayment_schedule.dart';
import '../../models/app_backup.dart';
import '../../models/group.dart';
import '../../models/loan.dart';
import '../../models/meeting.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/ipfs_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/notification_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/backup_service.dart';
import 'yaru_actions.dart';
import 'yaru_kit.dart';

// -----------------------------------------------------------------------------
// Onboarding
// -----------------------------------------------------------------------------

class YaruOnboardingPage extends ConsumerWidget {
  const YaruOnboardingPage({super.key});

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final picked = await FilePicker.pickFiles(withData: true);
    final bytes = picked?.files.single.bytes;
    if (bytes == null || !context.mounted) return;
    if (BackupEnvelope.tryDecode(bytes) == null) {
      yaruToast(context, 'That file is not a vBank backup', error: true);
      return;
    }
    final pin = await yaruPrompt(
      context,
      title: 'Restore backup',
      message: 'Enter the PIN you set when the backup was created.',
      label: 'Backup PIN',
      obscure: true,
      confirmLabel: 'Restore',
    );
    if (pin == null || !context.mounted) return;

    final service = BackupService();
    try {
      final restored = await service.decryptBackup(encryptedPayload: Uint8List.fromList(bytes), passphrase: pin);
      if (restored == null) {
        if (context.mounted) yaruToast(context, 'Invalid PIN or corrupted backup', error: true);
        return;
      }
      await service.importBackupFile(Uint8List.fromList(bytes));
      await service.applyBackup(restored);
      await ref.read(authProvider.notifier).loadIdentity();
      await ref.read(groupListProvider.notifier).refresh();
      if (context.mounted) {
        yaruToast(context, 'Restored ${restored.identity.displayName} and ${restored.groups.length} group(s)');
      }
    } catch (e) {
      if (context.mounted) yaruToast(context, 'Restore failed: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 460),
          child: Padding(
            padding: const EdgeInsets.all(40),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(YaruIcons.users, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 24),
                Text('vBank', style: theme.textTheme.headlineMedium),
                const SizedBox(height: 8),
                Text(
                  'Village banking that works offline. Your group’s books live on this computer and '
                  'sync directly with your members’ devices.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 32),
                FilledButton(
                  onPressed: () => yaruCreateIdentity(context, ref),
                  child: const Text('Get started'),
                ),
                const SizedBox(height: 8),
                OutlinedButton(
                  onPressed: () => _restore(context, ref),
                  child: const Text('Restore from backup'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Activity (all groups)
// -----------------------------------------------------------------------------

class YaruActivityPage extends ConsumerWidget {
  const YaruActivityPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final txs = ref.watch(allTransactionsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];

    return YaruDetailPage(
      appBar: AppBar(title: const Text('Activity')),
      body: txs.when(
        loading: () => const Center(child: YaruCircularProgressIndicator()),
        error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load activity', subtitle: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return const YaruEmpty(
              icon: YaruIcons.book,
              title: 'No transactions yet',
              subtitle: 'Records you and your co-admins make will appear here.',
            );
          }
          Group? groupOf(Transaction tx) => groups.where((g) => g.id == tx.groupId).firstOrNull;
          return YaruFilteredList<Transaction>(
            items: list,
            filters: transactionFilters(),
            searchHint: 'Search activity',
            searchText: (tx) => transactionHaystack(tx, group: groupOf(tx)),
            builder: (context, visible) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              itemCount: visible.length,
              itemBuilder: (context, i) => YaruTransactionTile(
                transaction: visible[i],
                group: groupOf(visible[i]),
                showGroup: true,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// One transaction row, Ubuntu style.
class YaruTransactionTile extends ConsumerWidget {
  final Transaction transaction;
  final Group? group;
  final bool showGroup;
  const YaruTransactionTile({
    super.key,
    required this.transaction,
    required this.group,
    this.showGroup = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final tx = transaction;
    final reversed = tx.status == TransactionStatus.reversed;
    final (icon, color) = switch (tx.type) {
      TransactionType.contribution => (YaruIcons.download, theme.colorScheme.primary),
      TransactionType.loan => (YaruIcons.book, theme.colorScheme.tertiary),
      TransactionType.repayment => (YaruIcons.sync, theme.colorScheme.primary),
      TransactionType.withdrawal => (YaruIcons.log_out, theme.colorScheme.secondary),
      TransactionType.penalty || TransactionType.fee => (YaruIcons.warning, Colors.orange),
      TransactionType.reversal => (YaruIcons.revert, theme.colorScheme.error),
    };
    String nameOf(String peerId) => peerId == 'group'
        ? 'Group fund'
        : group?.members.where((m) => m.peerId == peerId).firstOrNull?.name ?? 'member';

    return YaruListTile(
      leading: CircleAvatar(
        backgroundColor: color.withValues(alpha: 0.15),
        child: Icon(icon, color: color, size: 18),
      ),
      title: Text('${titleCase(tx.type.name)}${reversed ? ' (reversed)' : ''}'),
      subtitle: Text([
        if (showGroup && group != null) group!.name,
        fmtDate(tx.timestamp),
        '${nameOf(tx.fromPeerId)} → ${nameOf(tx.toPeerId)}',
        if (tx.note != null && tx.note!.isNotEmpty) tx.note!,
      ].join(' · ')),
      trailing: Text(
        fmtMoney(tx.currency, tx.amount),
        style: theme.textTheme.bodyLarge?.copyWith(
          fontWeight: FontWeight.w600,
          decoration: reversed ? TextDecoration.lineThrough : null,
        ),
      ),
      onTap: () => _showDetail(context, ref, nameOf),
    );
  }

  void _showDetail(BuildContext context, WidgetRef ref, String Function(String) nameOf) {
    final tx = transaction;
    final canWrite = ref.read(canWriteProvider);
    final me = ref.read(authProvider).identity?.peerId;
    final reversals = (ref.read(reversalsProvider(tx.groupId)).value ?? const [])
        .where((r) => r.originalTransactionId == tx.id)
        .toList();
    final pending = reversals.where((r) => r.isPending).firstOrNull;
    final involved = tx.fromPeerId == me || tx.toPeerId == me;

    yaruDialog<void>(
      context,
      title: titleCase(tx.type.name),
      width: 520,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          YaruInfoRow('Amount', fmtMoney(tx.currency, tx.amount)),
          YaruInfoRow('Status', titleCase(tx.status.name)),
          YaruInfoRow('From', nameOf(tx.fromPeerId)),
          YaruInfoRow('To', nameOf(tx.toPeerId)),
          YaruInfoRow('Recorded by', nameOf(tx.authorPeerId)),
          YaruInfoRow('When', fmtDateTime(tx.timestamp)),
          if (tx.note != null && tx.note!.isNotEmpty) YaruInfoRow('Note', tx.note!),
          YaruInfoRow('Sequence', '#${tx.sequenceNumber}'),
          if (reversals.isNotEmpty) ...[
            const SizedBox(height: 12),
            for (final r in reversals)
              YaruListTile(
                title: Text('Reversal ${r.status.name}'),
                subtitle: Text('${r.reason} — by ${nameOf(r.requestedByPeerId)}'),
                trailing: r.isPending && canWrite && r.requestedByPeerId != me
                    ? Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              yaruDecideReversal(context, ref, tx.groupId, r.id, approve: true);
                            },
                            child: const Text('Approve'),
                          ),
                          TextButton(
                            onPressed: () {
                              Navigator.pop(context);
                              yaruDecideReversal(context, ref, tx.groupId, r.id, approve: false);
                            },
                            child: const Text('Reject'),
                          ),
                        ],
                      )
                    : null,
              ),
          ],
        ],
      ),
      actions: (context) => [
        if (tx.status == TransactionStatus.confirmed && pending == null && (involved || canWrite))
          OutlinedButton.icon(
            icon: const Icon(YaruIcons.revert),
            label: const Text('Request reversal'),
            onPressed: () {
              Navigator.pop(context);
              yaruRequestReversal(context, ref, tx);
            },
          ),
        FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
      ],
    );
  }
}

// -----------------------------------------------------------------------------
// Meetings (all groups)
// -----------------------------------------------------------------------------

class YaruMeetingsPage extends ConsumerWidget {
  const YaruMeetingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meetings = ref.watch(upcomingMeetingsProvider);
    final groups = ref.watch(groupListProvider).value ?? const <Group>[];

    return YaruDetailPage(
      appBar: AppBar(title: const Text('Upcoming meetings')),
      body: meetings.when(
        loading: () => const Center(child: YaruCircularProgressIndicator()),
        error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load meetings', subtitle: '$e'),
        data: (list) {
          if (list.isEmpty) {
            return const YaruEmpty(
              icon: YaruIcons.calendar,
              title: 'No meetings scheduled',
              subtitle: 'Schedule one from a group’s Meetings tab.',
            );
          }
          String nameOf(Meeting m) => groups.where((g) => g.id == m.groupId).firstOrNull?.name ?? 'Meeting';
          return YaruFilteredList<Meeting>(
            items: list,
            filters: meetingFilters(),
            searchHint: 'Search meetings',
            searchText: (m) => meetingHaystack(m, group: nameOf(m)),
            builder: (context, visible) => ListView.builder(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              itemCount: visible.length,
              itemBuilder: (context, i) {
                final m = visible[i];
                final group = groups.where((g) => g.id == m.groupId).firstOrNull;
                return YaruListTile(
                  leading: const Icon(YaruIcons.calendar),
                  title: Text(nameOf(m)),
                  subtitle: Text('${fmtDateTime(m.scheduledAt)} · ${m.status.name}'),
                  trailing: const Icon(YaruIcons.pan_end),
                  onTap: group == null
                      ? null
                      : () {
                          ref.read(selectedGroupProvider.notifier).state = group;
                          Navigator.of(context, rootNavigator: true).push(
                            MaterialPageRoute(
                              builder: (_) => YaruMeetingDetailPage(groupId: group.id, meetingId: m.id),
                            ),
                          );
                        },
                );
              },
            ),
          );
        },
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Loan detail
// -----------------------------------------------------------------------------

class YaruLoanDetailPage extends ConsumerWidget {
  final String groupId;
  final String loanId;
  const YaruLoanDetailPage({super.key, required this.groupId, required this.loanId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final loanAsync = ref.watch(loanProvider(loanId));
    final scheduleAsync = ref.watch(loanScheduleProvider(loanId));
    final progress = ref.watch(loanProgressProvider(loanId)).value;
    final canWrite = ref.watch(canWriteProvider);
    final me = ref.watch(authProvider).identity?.peerId;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Loan')),
      body: loanAsync.when(
        loading: () => const Center(child: YaruCircularProgressIndicator()),
        error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load loan', subtitle: '$e'),
        data: (loan) {
          if (loan == null || group == null) {
            return const YaruEmpty(icon: YaruIcons.book, title: 'Loan not found');
          }
          final currency = group.config.currency;
          final borrower = group.members.where((m) => m.peerId == loan.borrowerPeerId).firstOrNull;
          final isBorrower = me == loan.borrowerPeerId;
          final schedule = scheduleAsync.value ?? const [];

          return ListView(
            padding: vbankPagePadding,
            children: [
              Row(
                children: [
                  Text(fmtMoney(currency, loan.requestedAmount), style: theme.textTheme.headlineSmall),
                  const SizedBox(width: 12),
                  YaruStatusChip(loan.status.name, color: _loanColor(theme, loan.status)),
                ],
              ),
              // Actions come first: the facts panel below grew (repaid, still owed,
              // approver…) and pushed the buttons below the fold on small windows.
              if (canWrite) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    if (loan.status == LoanStatus.pending && !isBorrower) ...[
                      FilledButton.icon(
                        icon: const Icon(YaruIcons.ok),
                        label: const Text('Approve'),
                        onPressed: () => yaruApproveLoan(context, ref, group, loan),
                      ),
                      OutlinedButton.icon(
                        icon: const Icon(YaruIcons.window_close),
                        label: const Text('Reject'),
                        onPressed: () => yaruRejectLoan(context, ref, group, loan),
                      ),
                    ],
                    if (loan.status == LoanStatus.pending && isBorrower)
                      Text('Another admin must approve your own request.',
                          style: theme.textTheme.bodySmall),
                    if (loan.status == LoanStatus.approved)
                      FilledButton.icon(
                        icon: const Icon(YaruIcons.download),
                        label: const Text('Record disbursement'),
                        onPressed: () => yaruDisburseLoan(context, ref, group, loan),
                      ),
                    if (loan.isActive)
                      FilledButton.icon(
                        icon: const Icon(YaruIcons.plus),
                        label: const Text('Record repayment'),
                        onPressed: () => yaruRecordRepayment(context, ref, group, loan, schedule),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
              YaruSection(
                headline: const Text('Loan'),
                child: Column(
                  children: [
                    YaruInfoRow('Borrower', borrower?.name ?? 'Unknown member'),
                    YaruInfoRow('Term', '${loan.termWeeks} weeks'),
                    YaruInfoRow('Interest', '${(loan.interestRate * 100).toStringAsFixed(0)}%'),
                    if (loan.approvedAmount > 0) YaruInfoRow('Approved', fmtMoney(currency, loan.approvedAmount)),
                    if (loan.approvedAmount > 0) YaruInfoRow('Total due', fmtMoney(currency, loan.totalWithInterest)),
                    if (progress != null && progress.totalDue > 0) ...[
                      YaruInfoRow('Repaid so far', fmtMoney(currency, progress.repaid)),
                      YaruInfoRow('Still owed', fmtMoney(currency, progress.remaining)),
                    ],
                    if (loan.approvedByPeerId != null)
                      YaruInfoRow('Approved by',
                          group.members.where((m) => m.peerId == loan.approvedByPeerId).firstOrNull?.name ?? 'Unknown member'),
                    if (loan.reason != null && loan.reason!.isNotEmpty) YaruInfoRow('Reason', loan.reason!),
                    YaruInfoRow('Requested', fmtDateTime(loan.requestedAt)),
                    if (loan.disbursedAt != null) YaruInfoRow('Disbursed', fmtDateTime(loan.disbursedAt!)),
                    if (loan.completedAt != null) YaruInfoRow('Completed', fmtDateTime(loan.completedAt!)),
                  ],
                ),
              ),
              if (progress != null && progress.repayments.isNotEmpty) ...[
                const SizedBox(height: 16),
                YaruSection(
                  headline: Text('Repayments (${progress.repayments.length})'),
                  child: Column(
                    children: [
                      for (final t in progress.repayments.reversed)
                        YaruListTile(
                          leading: const Icon(YaruIcons.refresh),
                          title: Text(fmtMoney(currency, t.amount)),
                          subtitle: Text(
                            '${fmtDate(t.timestamp)} · recorded by '
                            '${group.members.where((m) => m.peerId == t.authorPeerId).firstOrNull?.name ?? 'Unknown member'}',
                          ),
                        ),
                    ],
                  ),
                ),
              ],
              if (schedule.isNotEmpty) ...[
                const SizedBox(height: 16),
                YaruSection(
                  headline: const Text('Repayment schedule'),
                  child: Column(
                    children: [
                      for (final s in schedule)
                        YaruListTile(
                          leading: Icon(
                            s.isPaid
                                ? YaruIcons.ok
                                : s.isOverdue
                                    ? YaruIcons.warning
                                    : YaruIcons.clock,
                            color: s.isPaid
                                ? theme.colorScheme.primary
                                : s.isOverdue
                                    ? theme.colorScheme.error
                                    : theme.colorScheme.onSurfaceVariant,
                          ),
                          title: Text('Installment ${s.installmentNumber} — ${fmtMoney(currency, s.expectedAmount)}'),
                          subtitle: Text(
                            'Due ${fmtDate(s.dueDate)}'
                            '${s.paidAmount > 0 ? ' · paid ${s.paidAmount.toStringAsFixed(2)}' : ''}'
                            '${s.penalty > 0 ? ' · penalty ${s.penalty.toStringAsFixed(2)}' : ''}',
                          ),
                          trailing: YaruStatusChip(s.status.label),
                        ),
                    ],
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  static Color _loanColor(ThemeData theme, LoanStatus status) => switch (status) {
        LoanStatus.pending => Colors.orange,
        LoanStatus.approved || LoanStatus.disbursed || LoanStatus.repaying => theme.colorScheme.primary,
        LoanStatus.completed => theme.colorScheme.secondary,
        LoanStatus.rejected || LoanStatus.defaulted => theme.colorScheme.error,
      };
}

// -----------------------------------------------------------------------------
// Meeting detail
// -----------------------------------------------------------------------------

class YaruMeetingDetailPage extends ConsumerWidget {
  final String groupId;
  final String meetingId;
  const YaruMeetingDetailPage({super.key, required this.groupId, required this.meetingId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final group = ref.watch(groupListProvider).value?.where((g) => g.id == groupId).firstOrNull;
    final meetingAsync = ref.watch(meetingProvider(meetingId));
    final canWrite = ref.watch(canWriteProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Meeting')),
      body: meetingAsync.when(
        loading: () => const Center(child: YaruCircularProgressIndicator()),
        error: (e, _) => YaruEmpty(icon: YaruIcons.warning, title: 'Could not load meeting', subtitle: '$e'),
        data: (meeting) {
          if (meeting == null || group == null) {
            return const YaruEmpty(icon: YaruIcons.calendar, title: 'Meeting not found');
          }
          final editable = canWrite && meeting.status == MeetingStatus.scheduled;
          final members = group.members.where((m) => m.status == MemberStatus.active).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
          final present = meeting.attendance.where((a) => a.status == MeetingAttendanceStatus.present).length;
          final contributed = meeting.attendance.where((a) => a.contributed).length;

          return ListView(
            padding: vbankPagePadding,
            children: [
              Row(
                children: [
                  Text(fmtDateTime(meeting.scheduledAt), style: theme.textTheme.headlineSmall),
                  const SizedBox(width: 12),
                  YaruStatusChip(meeting.status.name),
                ],
              ),
              const SizedBox(height: 16),
              YaruSection(
                headline: const Text('Summary'),
                child: Column(
                  children: [
                    YaruInfoRow('Present', '$present / ${members.length}'),
                    YaruInfoRow('Contributed', '$contributed'),
                    if (meeting.status == MeetingStatus.completed)
                      YaruInfoRow('Collected', fmtMoney(group.config.currency, meeting.totalCollected)),
                    if (meeting.notes != null && meeting.notes!.isNotEmpty)
                      YaruInfoRow('Notes', meeting.notes!),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              YaruSection(
                headline: const Text('Attendance'),
                child: Column(
                  children: [
                    for (final m in members)
                      _AttendanceRow(
                        group: group,
                        meeting: meeting,
                        member: m,
                        editable: editable,
                      ),
                  ],
                ),
              ),
              if (editable) ...[
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(YaruIcons.ok),
                      label: const Text('Complete meeting'),
                      onPressed: () => yaruCompleteMeeting(context, ref, group, meeting, contributed),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(YaruIcons.window_close),
                      label: const Text('Cancel meeting'),
                      onPressed: () => yaruCancelMeeting(context, ref, group, meeting),
                    ),
                  ],
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _AttendanceRow extends ConsumerWidget {
  final Group group;
  final Meeting meeting;
  final Member member;
  final bool editable;
  const _AttendanceRow({
    required this.group,
    required this.meeting,
    required this.member,
    required this.editable,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final record = meeting.attendance.where((a) => a.peerId == member.peerId).firstOrNull;
    final status = record?.status ?? MeetingAttendanceStatus.absent;
    final paid = record?.contributed ?? false;
    const statuses = [
      MeetingAttendanceStatus.present,
      MeetingAttendanceStatus.excused,
      MeetingAttendanceStatus.absent,
    ];

    return YaruListTile(
      title: Text(member.name),
      subtitle: Text('${titleCase(status.name)}${paid ? ' · contributed' : ''}'),
      trailing: !editable
          ? null
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                YaruChoiceChipBar(
                  labels: [for (final s in statuses) Text(titleCase(s.name))],
                  isSelected: [for (final s in statuses) s == status],
                  onSelected: (i) => yaruSetAttendance(
                    context,
                    ref,
                    group,
                    meeting,
                    member.peerId,
                    statuses[i],
                    contributed: paid,
                  ),
                ),
                const SizedBox(width: 12),
                Tooltip(
                  message: 'Contributed',
                  child: YaruCheckbox(
                    value: paid,
                    onChanged: (v) => yaruSetAttendance(
                      context,
                      ref,
                      group,
                      meeting,
                      member.peerId,
                      v == true ? MeetingAttendanceStatus.present : status,
                      contributed: v ?? false,
                    ),
                  ),
                ),
              ],
            ),
    );
  }
}

// -----------------------------------------------------------------------------
// Sync
// -----------------------------------------------------------------------------

class YaruSyncPage extends ConsumerWidget {
  const YaruSyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final node = ref.watch(ipfsNodeStateProvider).value ?? ref.read(ipfsServiceProvider).state;
    final sync = ref.watch(syncStateProvider).value ?? ref.read(syncManagerProvider).state;
    final counts = ref.watch(syncCountsProvider).value ?? const {};
    final failed = ref.watch(failedTransactionsProvider).value ?? const <q.TransactionData>[];
    final log = ref.watch(syncLogProvider).value ?? const <SyncEvent>[];
    final manager = ref.read(syncManagerProvider);
    final peerId = ref.read(ipfsServiceProvider).peerId;
    final theme = Theme.of(context);

    return YaruDetailPage(
      appBar: AppBar(
        title: const Text('Sync'),
        actions: [
          IconButton(
            tooltip: 'Sync now',
            icon: const Icon(YaruIcons.sync),
            onPressed: sync == SyncState.syncing ? null : () => manager.startManualSync(),
          ),
        ],
      ),
      body: ListView(
        padding: vbankPagePadding,
        children: [
          YaruSection(
            headline: const Text('Network'),
            child: Column(
              children: [
                YaruInfoRow('Node', node.name),
                YaruInfoRow('Sync', sync.name),
                if (manager.lastSyncTime != null) YaruInfoRow('Last sync', fmtDateTime(manager.lastSyncTime!)),
                if (manager.lastError != null) YaruInfoRow('Last error', manager.lastError!),
                if (peerId != null) YaruInfoRow('Peer ID', peerId),
              ],
            ),
          ),
          const SizedBox(height: 16),
          YaruSection(
            headline: Row(
              children: [
                const Expanded(child: Text('Relay server')),
                TextButton.icon(
                  icon: const Icon(YaruIcons.plus),
                  label: const Text('Add'),
                  onPressed: () async {
                    final addr = await yaruPrompt(
                      context,
                      title: 'Relay server',
                      message: 'Paste the address printed by the relay (/ip4/…/tcp/4001/p2p/…). Members on other '
                          'networks reach each other through it; it never holds a group passphrase.',
                      label: 'Address',
                      confirmLabel: 'Add',
                    );
                    if (addr == null || !addr.contains('/p2p/') || !context.mounted) return;
                    await manager.addRelays([addr.trim()]);
                    ref.invalidate(relayAddressesProvider);
                    unawaited(manager.startManualSync());
                  },
                ),
              ],
            ),
            child: Builder(builder: (context) {
              final relays = ref.watch(relayAddressesProvider).value ?? const <String>[];
              if (relays.isEmpty) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('None. Members only reach each other on the same network. Add a relay to sync over the internet.'),
                );
              }
              return Column(
                children: [
                  for (final r in relays)
                    YaruListTile(
                      leading: const Icon(YaruIcons.network),
                      title: Text(r, style: theme.textTheme.bodySmall),
                      trailing: IconButton(
                        tooltip: 'Remove',
                        icon: const Icon(YaruIcons.trash),
                        onPressed: () async {
                          await manager.removeRelay(r);
                          ref.invalidate(relayAddressesProvider);
                        },
                      ),
                    ),
                ],
              );
            }),
          ),
          const SizedBox(height: 16),
          YaruSection(
            headline: const Text('Queue'),
            child: Column(
              children: [
                YaruInfoRow('Queued', '${counts[q.SyncStatus.queued] ?? 0}'),
                YaruInfoRow('Syncing', '${counts[q.SyncStatus.syncing] ?? 0}'),
                YaruInfoRow('Synced', '${counts[q.SyncStatus.synced] ?? 0}'),
                YaruInfoRow('Failed', '${counts[q.SyncStatus.failed] ?? 0}'),
              ],
            ),
          ),
          if (failed.isNotEmpty) ...[
            const SizedBox(height: 16),
            YaruSection(
              headline: Text('Failed after ${q.SyncStatus.maxAttempts} attempts'),
              child: Column(
                children: [
                  for (final t in failed)
                    YaruListTile(
                      leading: Icon(YaruIcons.warning, color: theme.colorScheme.error),
                      title: Text('${t.type} ${fmtMoney(t.currency, t.amount)}'),
                      subtitle: Text(t.lastSyncError ?? 'Unknown error'),
                      trailing: OutlinedButton(
                        onPressed: () async {
                          await ref.read(transactionServiceProvider).retry(t.id);
                          await manager.startManualSync();
                          ref.invalidate(failedTransactionsProvider);
                          ref.invalidate(syncCountsProvider);
                        },
                        child: const Text('Retry'),
                      ),
                    ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          YaruSection(
            headline: const Text('Activity log'),
            child: log.isEmpty
                ? const Padding(padding: EdgeInsets.all(16), child: Text('Nothing yet'))
                : Column(
                    children: [
                      for (final e in log.take(100))
                        YaruListTile(
                          leading: Icon(
                            switch (e.type) { SyncEventType.error => YaruIcons.error, SyncEventType.warning => YaruIcons.warning, _ => YaruIcons.ok },
                            size: 16,
                            color: switch (e.type) { SyncEventType.error => theme.colorScheme.error, SyncEventType.warning => Colors.amber.shade700, _ => theme.colorScheme.primary },
                          ),
                          title: Text(e.message),
                          subtitle: Text(fmtDateTime(e.timestamp)),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// -----------------------------------------------------------------------------
// Settings
// -----------------------------------------------------------------------------

class YaruSettingsPage extends ConsumerStatefulWidget {
  const YaruSettingsPage({super.key});

  @override
  ConsumerState<YaruSettingsPage> createState() => _YaruSettingsPageState();
}

class _YaruSettingsPageState extends ConsumerState<YaruSettingsPage> {
  final _service = BackupService();
  List<AppBackup> _backups = const [];

  @override
  void initState() {
    super.initState();
    _loadBackups();
  }

  Future<void> _loadBackups() async {
    final list = await _service.getAllBackups();
    if (mounted) setState(() => _backups = list);
  }

  @override
  Widget build(BuildContext context) {
    final identity = ref.watch(authProvider).identity;
    final prefs = ref.watch(notificationPrefsProvider);
    final prefsNotifier = ref.read(notificationPrefsProvider.notifier);
    final theme = Theme.of(context);

    return YaruDetailPage(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: vbankPagePadding,
        children: [
          YaruSection(
            headline: const Text('Identity'),
            child: Column(
              children: [
                YaruListTile(
                  leading: const Icon(YaruIcons.user),
                  title: Text(identity?.displayName ?? 'Not signed in'),
                  subtitle: Text(identity?.peerId ?? ''),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          YaruSection(
            headline: const Text('Notifications'),
            child: Column(
              children: [
                if (!AppPlatform.canNotify)
                  const YaruListTile(
                    leading: Icon(YaruIcons.information),
                    title: Text('Desktop notifications are not available on this platform'),
                  ),
                YaruSwitchListTile(
                  title: const Text('Enable notifications'),
                  value: prefs.enabled,
                  onChanged: (v) => prefsNotifier.set(SettingKeys.notificationsEnabled, v),
                ),
                YaruSwitchListTile(
                  title: const Text('Meeting reminders'),
                  subtitle: const Text('24 hours before each meeting'),
                  value: prefs.meetings,
                  onChanged: prefs.enabled ? (v) => prefsNotifier.set(SettingKeys.notifyMeetings, v) : null,
                ),
                YaruSwitchListTile(
                  title: const Text('Contribution due'),
                  value: prefs.contributions,
                  onChanged: prefs.enabled ? (v) => prefsNotifier.set(SettingKeys.notifyContributions, v) : null,
                ),
                YaruSwitchListTile(
                  title: const Text('Loan repayments'),
                  value: prefs.loans,
                  onChanged: prefs.enabled ? (v) => prefsNotifier.set(SettingKeys.notifyLoans, v) : null,
                ),
                YaruSwitchListTile(
                  title: const Text('Group activity'),
                  value: prefs.activity,
                  onChanged: prefs.enabled ? (v) => prefsNotifier.set(SettingKeys.notifyActivity, v) : null,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          YaruSection(
            headline: const Text('Backups'),
            child: Column(
              children: [
                YaruListTile(
                  leading: const Icon(YaruIcons.save),
                  title: const Text('Create a backup'),
                  subtitle: const Text('Identity, signing key, groups and group keys, encrypted with a PIN'),
                  trailing: FilledButton(
                    onPressed: () async {
                      await yaruCreateBackup(context, ref, _service);
                      await _loadBackups();
                    },
                    child: const Text('Create'),
                  ),
                ),
                for (final b in _backups)
                  YaruListTile(
                    leading: const Icon(YaruIcons.lock),
                    title: Text(fmtDateTime(b.createdAt)),
                    subtitle: Text('${(b.encryptedPayload.length / 1024).toStringAsFixed(1)} KB · encrypted'),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Export',
                          icon: const Icon(YaruIcons.download),
                          onPressed: () async {
                            try {
                              final file = await _service.exportBackupToFile(b.id);
                              if (context.mounted) yaruToast(context, 'Written to ${file.path}');
                            } catch (e) {
                              if (context.mounted) yaruToast(context, 'Export failed: $e', error: true);
                            }
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete',
                          icon: const Icon(YaruIcons.trash),
                          onPressed: () async {
                            final ok = await yaruConfirm(
                              context,
                              title: 'Delete backup?',
                              message: 'This cannot be undone. Exported copies are unaffected.',
                              confirmLabel: 'Delete',
                              destructive: true,
                            );
                            if (!ok) return;
                            await _service.deleteBackup(b.id);
                            await _loadBackups();
                          },
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
              icon: const Icon(YaruIcons.log_out),
              label: const Text('Log out'),
              onPressed: () async {
                final ok = await yaruConfirm(
                  context,
                  title: 'Log out?',
                  message: 'This removes your identity and keys from this computer. Without an exported '
                      'backup you cannot sign as this identity again.',
                  confirmLabel: 'Log out',
                  destructive: true,
                );
                if (ok) await ref.read(authProvider.notifier).logout();
              },
            ),
          ),
        ],
      ),
    );
  }
}
