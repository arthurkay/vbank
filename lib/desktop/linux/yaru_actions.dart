/// Every write action of the Linux shell, as Ubuntu-style dialogs.
///
/// The dialogs are thin: they collect input, call the same Riverpod notifiers
/// the mobile app uses, and report through a snack bar. All permission and
/// validation rules stay in the services (DESIGN_PLAN §13).
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../core/deeplink/deeplink_handler.dart';
import '../../core/deeplink/share_service.dart';
import '../../core/ipfs/sync_manager.dart';
import '../../core/presentation/list_filters.dart';
import '../../models/group.dart';
import '../../models/loan.dart';
import '../../models/meeting.dart';
import '../../models/repayment_schedule.dart';
import '../../models/transaction.dart';
import '../../providers/auth_provider.dart';
import '../../providers/data_version.dart';
import '../../providers/group_provider.dart';
import '../../providers/ipfs_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/backup_service.dart';
import '../../services/group_key_service.dart';
import 'yaru_kit.dart';

// -----------------------------------------------------------------------------
// Groups
// -----------------------------------------------------------------------------

Future<void> yaruCreateGroup(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final amount = TextEditingController(text: '20.00');
  final passphrase = TextEditingController();
  final confirm = TextEditingController();
  var frequency = ContributionFrequency.monthly;
  var requireApproval = false;
  String? error;

  final created = await yaruDialog<bool>(
    context,
    title: 'New group',
    width: 520,
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: name,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Group name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Contribution amount (ZMW)'),
          ),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Text('Contribution frequency', style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 6),
          YaruChoiceChipBar(
            labels: [for (final f in ContributionFrequency.values) Text(titleCase(f.name))],
            isSelected: [for (final f in ContributionFrequency.values) f == frequency],
            onSelected: (i) => setState(() => frequency = ContributionFrequency.values[i]),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: passphrase,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Group passphrase',
              helperText: 'Encrypts the group’s records. Share it with members in person.',
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: confirm,
            obscureText: true,
            decoration: InputDecoration(labelText: 'Confirm passphrase', errorText: error),
          ),
          const SizedBox(height: 8),
          YaruSwitchListTile(
            title: const Text('New members need approval'),
            value: requireApproval,
            onChanged: (v) => setState(() => requireApproval = v),
          ),
        ],
      ),
    ),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: () {
          final problem = GroupKeyService.validatePassphrase(passphrase.text) ??
              (passphrase.text != confirm.text ? 'Passphrases do not match' : null) ??
              (name.text.trim().isEmpty ? 'Give the group a name' : null) ??
              ((double.tryParse(amount.text) ?? 0) <= 0 ? 'Enter a contribution amount' : null);
          if (problem != null) {
            error = problem;
            yaruToast(context, problem, error: true);
            return;
          }
          Navigator.pop(context, true);
        },
        child: const Text('Create group'),
      ),
    ],
  );
  if (created != true || !context.mounted) return;

  try {
    final group = await ref.read(groupListProvider.notifier).createGroup(
          name: name.text.trim(),
          config: GroupConfig(
            groupId: '',
            contributionAmount: double.parse(amount.text),
            frequency: frequency,
          ),
          passphrase: passphrase.text,
          requireApproval: requireApproval,
        );
    ref.read(selectedGroupProvider.notifier).state = group;
    if (context.mounted) yaruToast(context, 'Created “${group.name}”');
  } catch (e) {
    debugPrint('[yaru] action failed: $e');
    if (context.mounted) yaruToast(context, '$e', error: true);
  }
}

Future<void> yaruEditGroupConfig(BuildContext context, WidgetRef ref, Group group) async {
  final cfg = group.config;
  final name = TextEditingController(text: group.name);
  final amount = TextEditingController(text: cfg.contributionAmount.toStringAsFixed(2));
  final interest = TextEditingController(text: (cfg.loanInterestRate * 100).toStringAsFixed(0));
  final penalty = TextEditingController(text: (cfg.latePenaltyRate * 100).toStringAsFixed(0));
  final multiplier = TextEditingController(text: cfg.maxLoanMultiplier.toString());
  final minContrib = TextEditingController(text: cfg.minContributionsForLoan.toString());
  var frequency = cfg.frequency;
  var requireLoanApproval = cfg.requireLoanApproval;
  var requireApproval = group.requireApproval;

  final save = await yaruDialog<bool>(
    context,
    title: 'Group configuration',
    width: 560,
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(controller: name, decoration: const InputDecoration(labelText: 'Group name')),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Contribution (${cfg.currency})'),
          ),
          const SizedBox(height: 16),
          Align(alignment: Alignment.centerLeft, child: Text('Frequency', style: Theme.of(context).textTheme.bodySmall)),
          const SizedBox(height: 6),
          YaruChoiceChipBar(
            labels: [for (final f in ContributionFrequency.values) Text(titleCase(f.name))],
            isSelected: [for (final f in ContributionFrequency.values) f == frequency],
            onSelected: (i) => setState(() => frequency = ContributionFrequency.values[i]),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: interest,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Loan interest (%)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: penalty,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Late penalty (%)'),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: TextField(
                controller: multiplier,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(labelText: 'Max loan (× contributions)'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextField(
                controller: minContrib,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Min contributions'),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          YaruSwitchListTile(
            title: const Text('Loans need admin approval'),
            value: requireLoanApproval,
            onChanged: (v) => setState(() => requireLoanApproval = v),
          ),
          YaruSwitchListTile(
            title: const Text('New members need approval'),
            value: requireApproval,
            onChanged: (v) => setState(() => requireApproval = v),
          ),
        ],
      ),
    ),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Save')),
    ],
  );
  if (save != true || !context.mounted) return;

  final updated = GroupConfig(
    groupId: group.id,
    contributionAmount: double.tryParse(amount.text) ?? cfg.contributionAmount,
    frequency: frequency,
    meetingDayOfWeek: cfg.meetingDayOfWeek,
    meetingTime: cfg.meetingTime,
    maxLoanMultiplier: double.tryParse(multiplier.text) ?? cfg.maxLoanMultiplier,
    loanInterestRate: (double.tryParse(interest.text) ?? cfg.loanInterestRate * 100) / 100,
    latePenaltyRate: (double.tryParse(penalty.text) ?? cfg.latePenaltyRate * 100) / 100,
    minContributionsForLoan: int.tryParse(minContrib.text) ?? cfg.minContributionsForLoan,
    currency: cfg.currency,
    savingsTarget: cfg.savingsTarget,
    requireLoanApproval: requireLoanApproval,
  );
  await _run(context, () async {
    await ref.read(groupListProvider.notifier).updateConfig(
          group.id,
          updated,
          requireApproval: requireApproval,
          name: name.text.trim() != group.name ? name.text.trim() : null,
        );
  }, 'Configuration saved');
}

// -----------------------------------------------------------------------------
// Transactions
// -----------------------------------------------------------------------------

Future<void> yaruRecordTransaction(BuildContext context, WidgetRef ref, Group group) async {
  final members = group.members.where((m) => m.status == MemberStatus.active).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (members.isEmpty) {
    yaruToast(context, 'This group has no active members yet', error: true);
    return;
  }
  final amount = TextEditingController(text: group.config.contributionAmount.toStringAsFixed(2));
  final note = TextEditingController();
  var type = TransactionType.contribution;
  var peerId = members.first.peerId;
  const selectable = [TransactionType.contribution, TransactionType.penalty, TransactionType.withdrawal];

  final ok = await yaruDialog<bool>(
    context,
    title: 'Record transaction',
    width: 520,
    content: StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          YaruChoiceChipBar(
            labels: [for (final t in selectable) Text(titleCase(t.name))],
            isSelected: [for (final t in selectable) t == type],
            onSelected: (i) => setState(() => type = selectable[i]),
          ),
          const SizedBox(height: 6),
          Text(
            'Loans and repayments are recorded from the loan itself.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<String>(
            initialValue: peerId,
            decoration: const InputDecoration(labelText: 'Member'),
            items: [for (final m in members) DropdownMenuItem(value: m.peerId, child: Text(m.name))],
            onChanged: (v) => setState(() => peerId = v ?? peerId),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: amount,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(labelText: 'Amount (${group.config.currency})'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            decoration: const InputDecoration(labelText: 'Note (optional)'),
          ),
        ],
      ),
    ),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Record')),
    ],
  );
  if (ok != true || !context.mounted) return;

  final value = double.tryParse(amount.text);
  if (value == null || value <= 0) {
    yaruToast(context, 'Enter a valid amount', error: true);
    return;
  }
  final (from, to) = switch (type) {
    TransactionType.withdrawal || TransactionType.loan => ('group', peerId),
    _ => (peerId, 'group'),
  };
  await _run(context, () async {
    await ref.read(transactionListProvider(group.id).notifier).createTransaction(
          fromPeerId: from,
          toPeerId: to,
          type: type,
          amount: value,
          note: note.text.trim().isEmpty ? null : note.text.trim(),
        );
  }, 'Transaction recorded');
}

Future<void> yaruRequestReversal(BuildContext context, WidgetRef ref, Transaction tx) async {
  final reason = await yaruPrompt(
    context,
    title: 'Request reversal',
    message: 'An admin has to approve the reversal before the transaction is undone.',
    label: 'Reason',
    confirmLabel: 'Request',
    maxLines: 2,
  );
  if (reason == null || reason.trim().isEmpty || !context.mounted) return;
  await _run(context, () async {
    await ref.read(transactionListProvider(tx.groupId).notifier).requestReversal(tx.id, reason.trim());
    ref.invalidate(reversalsProvider(tx.groupId));
  }, 'Reversal requested');
}

Future<void> yaruDecideReversal(
  BuildContext context,
  WidgetRef ref,
  String groupId,
  String reversalId, {
  required bool approve,
}) async {
  if (approve) {
    final ok = await yaruConfirm(
      context,
      title: 'Reverse this transaction?',
      message: 'A compensating record is written and the original is marked reversed. Both stay in the history.',
      confirmLabel: 'Reverse',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
  }
  await _run(context, () async {
    await ref.read(transactionListProvider(groupId).notifier).decideReversal(reversalId, approve: approve);
    ref.invalidate(reversalsProvider(groupId));
  }, approve ? 'Transaction reversed' : 'Reversal rejected');
}

// -----------------------------------------------------------------------------
// Loans
// -----------------------------------------------------------------------------

Future<void> yaruRequestLoan(BuildContext context, WidgetRef ref, Group group) async {
  final amount = TextEditingController();
  final term = TextEditingController(text: '4');
  final reason = TextEditingController();

  final ok = await yaruDialog<bool>(
    context,
    title: 'Request a loan',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Up to ${group.config.maxLoanMultiplier}× your contributions · '
          '${(group.config.loanInterestRate * 100).toStringAsFixed(0)}% interest · '
          'after ${group.config.minContributionsForLoan} contributions',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 16),
        TextField(
          controller: amount,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Amount (${group.config.currency})'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: term,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(labelText: 'Term (weeks)'),
        ),
        const SizedBox(height: 12),
        TextField(controller: reason, decoration: const InputDecoration(labelText: 'Reason (optional)')),
      ],
    ),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Submit request')),
    ],
  );
  if (ok != true || !context.mounted) return;

  final value = double.tryParse(amount.text);
  final weeks = int.tryParse(term.text);
  if (value == null || value <= 0 || weeks == null || weeks <= 0) {
    yaruToast(context, 'Enter a valid amount and term', error: true);
    return;
  }
  final notifier = ref.read(loanListProvider(group.id).notifier);
  final problems = await notifier.eligibilityProblems(value);
  if (problems.isNotEmpty) {
    if (context.mounted) yaruToast(context, 'Not eligible: ${problems.join('; ')}', error: true);
    return;
  }
  if (!context.mounted) return;
  await _run(context, () async {
    await notifier.requestLoan(
      requestedAmount: value,
      termWeeks: weeks,
      reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
    );
  }, 'Loan request submitted');
}

Future<void> yaruApproveLoan(BuildContext context, WidgetRef ref, Group group, LoanRequest loan) async {
  final text = await yaruPrompt(
    context,
    title: 'Approve loan',
    message: 'Up to ${fmtMoney(group.config.currency, loan.requestedAmount)} was requested.',
    label: 'Approved amount',
    initial: loan.requestedAmount.toStringAsFixed(2),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    confirmLabel: 'Approve',
  );
  final value = double.tryParse(text ?? '');
  if (value == null || value <= 0) return;
  if (!context.mounted) return;
  await _run(context, () async {
    await ref.read(loanListProvider(group.id).notifier).approveLoan(loanId: loan.id, approvedAmount: value);
  }, 'Loan approved');
}

Future<void> yaruRejectLoan(BuildContext context, WidgetRef ref, Group group, LoanRequest loan) async {
  final ok = await yaruConfirm(
    context,
    title: 'Reject this loan?',
    message: 'The borrower will see the request as rejected.',
    confirmLabel: 'Reject',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await _run(context, () async {
    await ref.read(loanListProvider(group.id).notifier).rejectLoan(loanId: loan.id);
  }, 'Loan rejected');
}

Future<void> yaruDisburseLoan(BuildContext context, WidgetRef ref, Group group, LoanRequest loan) async {
  await _run(context, () async {
    await ref.read(loanListProvider(group.id).notifier).disburseLoan(loanId: loan.id);
  }, 'Loan disbursed — repayment schedule created');
}

Future<void> yaruRecordRepayment(
  BuildContext context,
  WidgetRef ref,
  Group group,
  LoanRequest loan,
  List<RepaymentSchedule> schedule,
) async {
  final next = schedule.where((s) => !s.isPaid).firstOrNull;
  final suggested = next == null ? loan.weeklyPayment : next.remainingAmount + next.penalty;
  final text = await yaruPrompt(
    context,
    title: 'Record repayment',
    label: 'Amount (${group.config.currency})',
    initial: suggested.toStringAsFixed(2),
    keyboardType: const TextInputType.numberWithOptions(decimal: true),
    confirmLabel: 'Record',
  );
  final value = double.tryParse(text ?? '');
  if (value == null || value <= 0) return;
  if (!context.mounted) return;
  await _run(context, () async {
    await ref.read(loanListProvider(group.id).notifier).recordRepayment(loanId: loan.id, amount: value);
  }, 'Repayment recorded');
}

// -----------------------------------------------------------------------------
// Meetings
// -----------------------------------------------------------------------------

Future<void> yaruScheduleMeeting(BuildContext context, WidgetRef ref, Group group) async {
  final now = DateTime.now();
  final date = await showDatePicker(
    context: context,
    initialDate: now.add(const Duration(days: 7)),
    firstDate: now,
    lastDate: now.add(const Duration(days: 365)),
  );
  if (date == null || !context.mounted) return;
  final parts = group.config.meetingTime.split(':');
  final time = await showTimePicker(
    context: context,
    initialTime: TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: int.tryParse(parts.last) ?? 0),
  );
  if (time == null || !context.mounted) return;

  final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  await _run(context, () async {
    await ref.read(meetingListProvider(group.id).notifier).createMeeting(scheduledAt: when);
  }, 'Meeting scheduled');
}

Future<void> yaruCompleteMeeting(
  BuildContext context,
  WidgetRef ref,
  Group group,
  Meeting meeting,
  int contributed,
) async {
  final total = TextEditingController(
    text: (contributed * group.config.contributionAmount).toStringAsFixed(2),
  );
  final notes = TextEditingController(text: meeting.notes ?? '');
  final ok = await yaruDialog<bool>(
    context,
    title: 'Complete meeting',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: total,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(labelText: 'Total collected (${group.config.currency})'),
        ),
        const SizedBox(height: 12),
        TextField(controller: notes, maxLines: 3, decoration: const InputDecoration(labelText: 'Notes')),
      ],
    ),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Complete')),
    ],
  );
  if (ok != true || !context.mounted) return;
  await _run(context, () async {
    await ref.read(meetingListProvider(group.id).notifier).completeMeeting(
          meetingId: meeting.id,
          totalCollected: double.tryParse(total.text) ?? 0,
          notes: notes.text.trim(),
        );
    ref.invalidate(meetingProvider(meeting.id));
  }, 'Meeting completed');
}

Future<void> yaruCancelMeeting(BuildContext context, WidgetRef ref, Group group, Meeting meeting) async {
  final ok = await yaruConfirm(
    context,
    title: 'Cancel this meeting?',
    message: 'Members will be told the meeting is cancelled.',
    confirmLabel: 'Cancel meeting',
    cancelLabel: 'Keep',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await _run(context, () async {
    await ref.read(meetingListProvider(group.id).notifier).cancelMeeting(meeting.id);
    ref.invalidate(meetingProvider(meeting.id));
  }, 'Meeting cancelled');
}

Future<void> yaruSetAttendance(
  BuildContext context,
  WidgetRef ref,
  Group group,
  Meeting meeting,
  String peerId,
  MeetingAttendanceStatus status, {
  required bool contributed,
}) async {
  await _run(context, () async {
    await ref.read(meetingListProvider(group.id).notifier).recordAttendance(
          meetingId: meeting.id,
          peerId: peerId,
          status: status,
          contributed: contributed,
        );
    ref.invalidate(meetingProvider(meeting.id));
  }, null);
}

// -----------------------------------------------------------------------------
// Members and governance
// -----------------------------------------------------------------------------

Future<void> yaruMemberAction(
  BuildContext context,
  WidgetRef ref,
  Group group,
  Member member,
  String action,
) async {
  final notifier = ref.read(groupListProvider.notifier);
  switch (action) {
    case 'approve':
      await _run(context, () => notifier.approveMember(group.id, member.peerId), '${member.name} approved');
    case 'reject':
      await _run(context, () => notifier.rejectMember(group.id, member.peerId), '${member.name} rejected');
    case 'promote':
      await _run(context, () => notifier.setRole(group.id, member.peerId, MemberRole.admin),
          '${member.name} is now an admin');
    case 'demote':
      await _run(context, () => notifier.setRole(group.id, member.peerId, MemberRole.member),
          '${member.name} is now a member');
    case 'suspend':
      await _run(context, () => notifier.setStatus(group.id, member.peerId, MemberStatus.suspended),
          '${member.name} suspended');
    case 'reinstate':
      await _run(context, () => notifier.setStatus(group.id, member.peerId, MemberStatus.active),
          '${member.name} reinstated');
    case 'transfer':
      final ok = await yaruConfirm(
        context,
        title: 'Transfer ownership to ${member.name}?',
        message: 'You become an admin. ${member.name}’s device countersigns on its next sync.',
        confirmLabel: 'Transfer',
      );
      if (ok && context.mounted) {
        await _run(context, () => notifier.transferOwnership(group.id, member.peerId),
            'Ownership transferred to ${member.name}');
      }
    case 'remove':
      final reason = TextEditingController();
      var writeOff = false;
      final ok = await yaruDialog<bool>(
        context,
        title: 'Remove ${member.name}?',
        content: StatefulBuilder(
          builder: (context, setState) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: reason,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Reason'),
              ),
              if (member.hasOutstandingLoan)
                YaruCheckboxListTile(
                  value: writeOff,
                  onChanged: (v) => setState(() => writeOff = v ?? false),
                  title: const Text('Write off outstanding loan'),
                  subtitle: const Text('Marks the loan defaulted and records the amount'),
                ),
            ],
          ),
        ),
        actions: (context) => [
          OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remove'),
          ),
        ],
      );
      if (ok == true && context.mounted) {
        await _run(
          context,
          () => notifier.removeMember(
            group.id,
            member.peerId,
            reason.text.trim().isEmpty ? 'Removed by owner' : reason.text.trim(),
            writeOffLoan: writeOff,
          ),
          '${member.name} removed',
        );
      }
  }
}

Future<void> yaruDissolveGroup(BuildContext context, WidgetRef ref, Group group) async {
  final blockers = await ref.read(governanceServiceProvider).dissolutionBlockers(group.id);
  if (!context.mounted) return;
  if (blockers.isNotEmpty) {
    yaruToast(context, 'Cannot dissolve: ${blockers.join('; ')}', error: true);
    return;
  }
  final ok = await yaruConfirm(
    context,
    title: 'Dissolve ${group.name}?',
    message: 'Every member is paid out their net balance and the group becomes read-only. This cannot be undone.',
    confirmLabel: 'Dissolve',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await _run(context, () => ref.read(groupListProvider.notifier).dissolveGroup(group.id), 'Group dissolved');
}

// -----------------------------------------------------------------------------
// Invites and joining
// -----------------------------------------------------------------------------

Future<void> yaruShowInvite(BuildContext context, WidgetRef ref, Group group) async {
  final identity = ref.read(authProvider).identity;
  if (identity == null) return;
  String? link;
  Object? error;
  try {
    final invite = await ref.read(syncManagerProvider).createInvite(group.id);
    link = DeepLinkHandler.buildJoinLink(
      groupId: group.id,
      inviterPeerId: identity.peerId,
      groupCid: invite.cid,
      inviteId: invite.id,
      inviteNonceB64: base64Encode(invite.nonce!),
      inviterAddrs: await ref.read(syncManagerProvider).inviteAddresses(group.id),
      relayAddrs: await ref.read(syncManagerProvider).userRelayAddresses(),
    );
  } catch (e) {
    error = e;
  }
  if (!context.mounted) return;

  await yaruDialog<void>(
    context,
    title: 'Invite to ${group.name}',
    width: 560,
    content: error != null
        ? Text('Could not create an invite: $error')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'This invite works once and expires. Tell the new member the group passphrase in '
                'person — it is not in the link.',
              ),
              const SizedBox(height: 16),
              SelectableText(link!, style: const TextStyle(fontFamily: 'monospace', fontSize: 12)),
            ],
          ),
    actions: (context) => [
      if (error == null)
        OutlinedButton.icon(
          icon: const Icon(YaruIcons.copy),
          label: const Text('Copy link'),
          onPressed: () async {
            await ShareService.copyToClipboard(link!);
            if (context.mounted) {
              Navigator.pop(context);
              yaruToast(context, 'Invite link copied');
            }
          },
        ),
      FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
    ],
  );
}

Future<void> yaruJoinGroup(BuildContext context, WidgetRef ref) async {
  final linkText = await yaruPrompt(
    context,
    title: 'Join a group',
    message: 'Paste the invite link an admin sent you. On this platform there is no camera scanner, '
        'so the link is entered by hand.',
    label: 'Invite link',
    confirmLabel: 'Continue',
    maxLines: 3,
  );
  if (linkText == null || linkText.trim().isEmpty || !context.mounted) return;

  final result = DeepLinkHandler.parseString(linkText.trim());
  final groupId = result.groupId;
  if (!result.isJoin || groupId == null || result.inviterPeerId == null) {
    yaruToast(context, result.error ?? 'That does not look like a vBank invite', error: true);
    return;
  }
  final identity = ref.read(authProvider).identity;
  if (identity == null) return;

  final passphrase = await yaruPrompt(
    context,
    title: 'Group passphrase',
    message: 'Ask the person who invited you. It unlocks the group’s records on this computer.',
    label: 'Passphrase',
    obscure: true,
    confirmLabel: 'Join',
  );
  if (passphrase == null || !context.mounted) return;
  final problem = GroupKeyService.validatePassphrase(passphrase);
  if (problem != null) {
    yaruToast(context, problem, error: true);
    return;
  }

  try {
    final keyPair = await ref.read(authProvider.notifier).requireSigningKeyPair();
    final self = Member(
      peerId: identity.peerId,
      name: identity.displayName,
      role: MemberRole.member,
      joinedAt: DateTime.now().toUtc(),
      publicKey: identity.publicKey,
    );
    if (result.relayAddrs.isNotEmpty) await ref.read(syncManagerProvider).addRelays(result.relayAddrs);
    final group = await ref.read(syncManagerProvider).joinGroup(
          groupId: groupId,
          groupCid: result.groupCid,
          inviteId: result.inviteId,
          inviteNonceB64: result.inviteNonceB64,
          inviterPeerId: result.inviterPeerId,
          inviterAddrs: result.inviterAddrs,
          passphrase: passphrase,
          self: self,
          keyPair: keyPair,
        );
    await ref.read(groupListProvider.notifier).refresh();
    ref.read(selectedGroupProvider.notifier).state = group;
    if (context.mounted) {
      yaruToast(
        context,
        group.requireApproval
            ? 'Join request sent to “${group.name}”'
            : 'Joined “${group.name}”',
      );
    }
  } on JoinParkedException catch (e) {
    ref.read(dataVersionProvider.notifier).state++;
    if (context.mounted) yaruToast(context, e.message);
  } on JoinGroupException catch (e) {
    if (context.mounted) yaruToast(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) yaruToast(context, 'Could not join: $e', error: true);
  }
}

// -----------------------------------------------------------------------------
// Identity and backups
// -----------------------------------------------------------------------------

Future<void> yaruCreateIdentity(BuildContext context, WidgetRef ref) async {
  final name = await yaruPrompt(
    context,
    title: 'Welcome to vBank',
    message: 'Enter the name your group knows you by. No phone number, no email, no account — vBank '
        'creates a signing key on this computer.',
    label: 'Display name',
    confirmLabel: 'Get started',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  await _run(context, () async {
    await ref.read(authProvider.notifier).createIdentity(name.trim());
  }, 'Identity created');
}

Future<void> yaruCreateBackup(BuildContext context, WidgetRef ref, BackupService service) async {
  final pin1 = TextEditingController();
  final pin2 = TextEditingController();
  final ok = await yaruDialog<bool>(
    context,
    title: 'Backup PIN',
    content: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          'This PIN protects your signing key and all group keys. Anyone with the file and the PIN '
          'can act as you — choose at least 6 characters.',
        ),
        const SizedBox(height: 16),
        TextField(
          controller: pin1,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(labelText: 'PIN'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: pin2,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Confirm PIN'),
        ),
      ],
    ),
    actions: (context) => [
      OutlinedButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Create backup')),
    ],
  );
  if (ok != true || !context.mounted) return;

  final problem = BackupService.validatePin(pin1.text) ??
      (pin1.text != pin2.text ? 'PINs do not match' : null);
  if (problem != null) {
    yaruToast(context, problem, error: true);
    return;
  }
  try {
    final id = await service.createFullBackup(passphrase: pin1.text);
    final file = await service.exportBackupToFile(id);
    if (context.mounted) yaruToast(context, 'Backup written to ${file.path}');
  } catch (e) {
    if (context.mounted) yaruToast(context, 'Backup failed: $e', error: true);
  }
}

// -----------------------------------------------------------------------------

/// Runs [action], reporting success or the error through a snack bar.
Future<void> _run(BuildContext context, Future<void> Function() action, String? success) async {
  try {
    await action();
    if (context.mounted && success != null) yaruToast(context, success);
  } catch (e) {
    debugPrint('[yaru] action failed: $e');
    if (context.mounted) yaruToast(context, '$e', error: true);
  }
}
