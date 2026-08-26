/// Write actions for the macOS shell, as sheets and alerts.
library;

import 'dart:convert';

import 'package:flutter/material.dart' show SelectableText, TimeOfDay;
import 'package:flutter/widgets.dart';
import 'package:macos_ui/macos_ui.dart';

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
import '../../providers/group_provider.dart';
import '../../providers/ipfs_provider.dart';
import '../../providers/loan_provider.dart';
import '../../providers/meeting_provider.dart';
import '../../providers/transaction_provider.dart';
import '../../services/backup_service.dart';
import '../../services/group_key_service.dart';
import 'macos_kit.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

// -----------------------------------------------------------------------------
// Groups
// -----------------------------------------------------------------------------

Future<void> macosCreateGroup(BuildContext context, WidgetRef ref) async {
  final name = TextEditingController();
  final amount = TextEditingController(text: '20.00');
  final passphrase = TextEditingController();
  final confirm = TextEditingController();
  var frequency = ContributionFrequency.weekly;
  var requireApproval = false;

  final ok = await macosSheet<bool>(
    context,
    title: 'New group',
    width: 520,
    content: (context) => StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(context, 'Group name'),
          MacosTextField(controller: name, placeholder: 'Ngombe Circle', autofocus: true),
          const SizedBox(height: 12),
          _label(context, 'Contribution amount'),
          MacosTextField(controller: amount, placeholder: '20.00'),
          const SizedBox(height: 12),
          _label(context, 'Frequency'),
          MacosPopupButton<ContributionFrequency>(
            value: frequency,
            items: [
              for (final f in ContributionFrequency.values)
                MacosPopupMenuItem(value: f, child: Text(titleCase(f.name))),
            ],
            onChanged: (v) => setState(() => frequency = v ?? frequency),
          ),
          const SizedBox(height: 12),
          _label(context, 'Group passphrase'),
          MacosTextField(controller: passphrase, obscureText: true),
          const SizedBox(height: 8),
          _label(context, 'Confirm passphrase'),
          MacosTextField(controller: confirm, obscureText: true),
          const SizedBox(height: 12),
          Row(children: [
            MacosSwitch(value: requireApproval, onChanged: (v) => setState(() => requireApproval = v)),
            const SizedBox(width: 10),
            const Text('New members need approval'),
          ]),
        ],
      ),
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Create'),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;

  final problem = GroupKeyService.validatePassphrase(passphrase.text) ??
      (passphrase.text != confirm.text ? 'Passphrases do not match' : null) ??
      (name.text.trim().isEmpty ? 'Give the group a name' : null) ??
      ((double.tryParse(amount.text) ?? 0) <= 0 ? 'Enter a contribution amount' : null);
  if (problem != null) {
    await macosToast(context, problem, error: true);
    return;
  }
  await _run(context, () async {
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
  }, null);
}

Future<void> macosEditGroupConfig(BuildContext context, WidgetRef ref, Group group) async {
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

  final ok = await macosSheet<bool>(
    context,
    title: 'Group configuration',
    width: 560,
    content: (context) => StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(context, 'Group name'),
          MacosTextField(controller: name),
          const SizedBox(height: 12),
          _label(context, 'Contribution (${cfg.currency})'),
          MacosTextField(controller: amount),
          const SizedBox(height: 12),
          _label(context, 'Frequency'),
          MacosPopupButton<ContributionFrequency>(
            value: frequency,
            items: [
              for (final f in ContributionFrequency.values)
                MacosPopupMenuItem(value: f, child: Text(titleCase(f.name))),
            ],
            onChanged: (v) => setState(() => frequency = v ?? frequency),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label(context, 'Loan interest (%)'),
                MacosTextField(controller: interest),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label(context, 'Late penalty (%)'),
                MacosTextField(controller: penalty),
              ]),
            ),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label(context, 'Max loan (×)'),
                MacosTextField(controller: multiplier),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _label(context, 'Min contributions'),
                MacosTextField(controller: minContrib),
              ]),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            MacosSwitch(
                value: requireLoanApproval, onChanged: (v) => setState(() => requireLoanApproval = v)),
            const SizedBox(width: 10),
            const Text('Loans need admin approval'),
          ]),
          const SizedBox(height: 8),
          Row(children: [
            MacosSwitch(value: requireApproval, onChanged: (v) => setState(() => requireApproval = v)),
            const SizedBox(width: 10),
            const Text('New members need approval'),
          ]),
        ],
      ),
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Save'),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;

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

Future<void> macosRecordTransaction(BuildContext context, WidgetRef ref, Group group) async {
  final members = group.members.where((m) => m.status == MemberStatus.active).toList()
    ..sort((a, b) => a.name.compareTo(b.name));
  if (members.isEmpty) {
    await macosToast(context, 'This group has no active members yet', error: true);
    return;
  }
  final amount = TextEditingController(text: group.config.contributionAmount.toStringAsFixed(2));
  final note = TextEditingController();
  var type = TransactionType.contribution;
  var peerId = members.first.peerId;
  const selectable = [TransactionType.contribution, TransactionType.penalty, TransactionType.withdrawal];

  final ok = await macosSheet<bool>(
    context,
    title: 'Record transaction',
    content: (context) => StatefulBuilder(
      builder: (context, setState) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _label(context, 'Type'),
          MacosPopupButton<TransactionType>(
            value: type,
            items: [
              for (final t in selectable) MacosPopupMenuItem(value: t, child: Text(titleCase(t.name))),
            ],
            onChanged: (v) => setState(() => type = v ?? type),
          ),
          const SizedBox(height: 6),
          Text('Loans and repayments are recorded from the loan itself.',
              style: MacosTheme.of(context).typography.caption1),
          const SizedBox(height: 12),
          _label(context, 'Member'),
          MacosPopupButton<String>(
            value: peerId,
            items: [for (final m in members) MacosPopupMenuItem(value: m.peerId, child: Text(m.name))],
            onChanged: (v) => setState(() => peerId = v ?? peerId),
          ),
          const SizedBox(height: 12),
          _label(context, 'Amount (${group.config.currency})'),
          MacosTextField(controller: amount, autofocus: true),
          const SizedBox(height: 12),
          _label(context, 'Note (optional)'),
          MacosTextField(controller: note),
        ],
      ),
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Record'),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;

  final value = double.tryParse(amount.text);
  if (value == null || value <= 0) {
    await macosToast(context, 'Enter a valid amount', error: true);
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
  }, null);
}

Future<void> macosRequestReversal(BuildContext context, WidgetRef ref, Transaction tx) async {
  final reason = await macosPrompt(
    context,
    title: 'Request reversal',
    message: 'An admin has to approve the reversal before the transaction is undone.',
    placeholder: 'e.g. recorded twice',
    confirmLabel: 'Request',
  );
  if (reason == null || reason.trim().isEmpty || !context.mounted) return;
  await _run(context, () async {
    await ref.read(transactionListProvider(tx.groupId).notifier).requestReversal(tx.id, reason.trim());
    ref.invalidate(reversalsProvider(tx.groupId));
  }, 'Reversal requested');
}

Future<void> macosDecideReversal(
  BuildContext context,
  WidgetRef ref,
  String groupId,
  String reversalId, {
  required bool approve,
}) async {
  if (approve) {
    final ok = await macosConfirm(
      context,
      title: 'Reverse this transaction?',
      message: 'A compensating record is written and the original is marked reversed.',
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

Future<void> macosRequestLoan(BuildContext context, WidgetRef ref, Group group) async {
  final amount = TextEditingController();
  final term = TextEditingController(text: '4');
  final reason = TextEditingController();

  final ok = await macosSheet<bool>(
    context,
    title: 'Request a loan',
    content: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Up to ${group.config.maxLoanMultiplier}× your contributions · '
          '${(group.config.loanInterestRate * 100).toStringAsFixed(0)}% interest',
          style: MacosTheme.of(context).typography.caption1,
        ),
        const SizedBox(height: 14),
        _label(context, 'Amount (${group.config.currency})'),
        MacosTextField(controller: amount, autofocus: true),
        const SizedBox(height: 12),
        _label(context, 'Term (weeks)'),
        MacosTextField(controller: term),
        const SizedBox(height: 12),
        _label(context, 'Reason (optional)'),
        MacosTextField(controller: reason),
      ],
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Submit'),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;

  final value = double.tryParse(amount.text);
  final weeks = int.tryParse(term.text);
  if (value == null || value <= 0 || weeks == null || weeks <= 0) {
    await macosToast(context, 'Enter a valid amount and term', error: true);
    return;
  }
  final notifier = ref.read(loanListProvider(group.id).notifier);
  final problems = await notifier.eligibilityProblems(value);
  if (!context.mounted) return;
  if (problems.isNotEmpty) {
    await macosToast(context, 'Not eligible: ${problems.join('; ')}', error: true);
    return;
  }
  await _run(context, () async {
    await notifier.requestLoan(
      requestedAmount: value,
      termWeeks: weeks,
      reason: reason.text.trim().isEmpty ? null : reason.text.trim(),
    );
  }, null);
}

Future<void> macosApproveLoan(BuildContext context, WidgetRef ref, Group group, LoanRequest loan) async {
  final text = await macosPrompt(
    context,
    title: 'Approve loan',
    message: 'Up to ${fmtMoney(group.config.currency, loan.requestedAmount)} was requested.',
    initial: loan.requestedAmount.toStringAsFixed(2),
    confirmLabel: 'Approve',
  );
  final value = double.tryParse(text ?? '');
  if (value == null || value <= 0 || !context.mounted) return;
  await _run(context, () async {
    await ref.read(loanListProvider(group.id).notifier).approveLoan(loanId: loan.id, approvedAmount: value);
  }, 'Loan approved');
}

Future<void> macosRejectLoan(BuildContext context, WidgetRef ref, Group group, LoanRequest loan) async {
  final ok = await macosConfirm(
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

Future<void> macosDisburseLoan(BuildContext context, WidgetRef ref, Group group, LoanRequest loan) async {
  await _run(context, () async {
    await ref.read(loanListProvider(group.id).notifier).disburseLoan(loanId: loan.id);
  }, 'Loan disbursed — repayment schedule created');
}

Future<void> macosRecordRepayment(
  BuildContext context,
  WidgetRef ref,
  Group group,
  LoanRequest loan,
  List<RepaymentSchedule> schedule,
) async {
  final next = schedule.where((s) => !s.isPaid).firstOrNull;
  final suggested = next == null ? loan.weeklyPayment : next.remainingAmount + next.penalty;
  final text = await macosPrompt(
    context,
    title: 'Record repayment',
    message: 'Amount in ${group.config.currency}.',
    initial: suggested.toStringAsFixed(2),
    confirmLabel: 'Record',
  );
  final value = double.tryParse(text ?? '');
  if (value == null || value <= 0 || !context.mounted) return;
  await _run(context, () async {
    await ref.read(loanListProvider(group.id).notifier).recordRepayment(loanId: loan.id, amount: value);
  }, 'Repayment recorded');
}

// -----------------------------------------------------------------------------
// Meetings
// -----------------------------------------------------------------------------

Future<void> macosScheduleMeeting(BuildContext context, WidgetRef ref, Group group) async {
  var date = DateTime.now().add(const Duration(days: 7));
  final parts = group.config.meetingTime.split(':');
  var time = TimeOfDay(hour: int.tryParse(parts.first) ?? 9, minute: int.tryParse(parts.last) ?? 0);

  final ok = await macosSheet<bool>(
    context,
    title: 'Schedule meeting',
    width: 520,
    content: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, 'Date'),
        MacosDatePicker(
          initialDate: date,
          onDateChanged: (value) => date = value,
        ),
        const SizedBox(height: 16),
        _label(context, 'Time'),
        MacosTimePicker(
          initialTime: time,
          onTimeChanged: (value) => time = value,
        ),
      ],
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Schedule'),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;

  final when = DateTime(date.year, date.month, date.day, time.hour, time.minute);
  if (when.isBefore(DateTime.now())) {
    await macosToast(context, 'Pick a time in the future', error: true);
    return;
  }
  await _run(context, () async {
    await ref.read(meetingListProvider(group.id).notifier).createMeeting(scheduledAt: when);
  }, null);
}

Future<void> macosCompleteMeeting(
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
  final ok = await macosSheet<bool>(
    context,
    title: 'Complete meeting',
    content: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        _label(context, 'Total collected (${group.config.currency})'),
        MacosTextField(controller: total, autofocus: true),
        const SizedBox(height: 12),
        _label(context, 'Notes'),
        MacosTextField(controller: notes, maxLines: 3),
      ],
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Complete'),
      ),
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

Future<void> macosCancelMeeting(BuildContext context, WidgetRef ref, Group group, Meeting meeting) async {
  final ok = await macosConfirm(
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

Future<void> macosSetAttendance(
  WidgetRef ref,
  Group group,
  Meeting meeting,
  String peerId,
  MeetingAttendanceStatus status, {
  required bool contributed,
}) async {
  await ref.read(meetingListProvider(group.id).notifier).recordAttendance(
        meetingId: meeting.id,
        peerId: peerId,
        status: status,
        contributed: contributed,
      );
  ref.invalidate(meetingProvider(meeting.id));
}

// -----------------------------------------------------------------------------
// Members, invites, identity
// -----------------------------------------------------------------------------

Future<void> macosMemberAction(
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
      final ok = await macosConfirm(
        context,
        title: 'Transfer ownership to ${member.name}?',
        message: 'You become an admin. Their device countersigns on its next sync.',
        confirmLabel: 'Transfer',
      );
      if (ok && context.mounted) {
        await _run(context, () => notifier.transferOwnership(group.id, member.peerId),
            'Ownership transferred');
      }
    case 'remove':
      final reason = await macosPrompt(
        context,
        title: 'Remove ${member.name}?',
        message: member.hasOutstandingLoan
            ? 'This member has an outstanding loan; removing them writes it off as defaulted.'
            : 'Give a reason for the record.',
        placeholder: 'Reason',
        confirmLabel: 'Remove',
      );
      if (reason == null || !context.mounted) return;
      await _run(
        context,
        () => notifier.removeMember(
          group.id,
          member.peerId,
          reason.trim().isEmpty ? 'Removed by owner' : reason.trim(),
          writeOffLoan: member.hasOutstandingLoan,
        ),
        '${member.name} removed',
      );
  }
}

Future<void> macosDissolveGroup(BuildContext context, WidgetRef ref, Group group) async {
  final blockers = await ref.read(governanceServiceProvider).dissolutionBlockers(group.id);
  if (!context.mounted) return;
  if (blockers.isNotEmpty) {
    await macosToast(context, 'Cannot dissolve: ${blockers.join('; ')}', error: true);
    return;
  }
  final ok = await macosConfirm(
    context,
    title: 'Dissolve ${group.name}?',
    message: 'Every member is paid out their net balance and the group becomes read-only.',
    confirmLabel: 'Dissolve',
    destructive: true,
  );
  if (!ok || !context.mounted) return;
  await _run(context, () => ref.read(groupListProvider.notifier).dissolveGroup(group.id), 'Group dissolved');
}

Future<void> macosShowInvite(BuildContext context, WidgetRef ref, Group group) async {
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
      inviterAddrs: ref.read(syncManagerProvider).dialableAddresses,
    );
  } catch (e) {
    error = e;
  }
  if (!context.mounted) return;

  await macosSheet<void>(
    context,
    title: 'Invite to ${group.name}',
    width: 560,
    content: (context) => error != null
        ? Text('Could not create an invite: $error')
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'This invite works once and expires. Tell the new member the group passphrase in '
                'person — it is not in the link.',
                style: MacosTheme.of(context).typography.body,
              ),
              const SizedBox(height: 14),
              SelectableText(link!, style: MacosTheme.of(context).typography.caption1),
            ],
          ),
    actions: (context) => [
      if (error == null)
        PushButton(
          controlSize: ControlSize.large,
          secondary: true,
          onPressed: () async {
            await ShareService.copyToClipboard(link!);
            if (context.mounted) Navigator.pop(context);
          },
          child: const Text('Copy link'),
        ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context),
        child: const Text('Done'),
      ),
    ],
  );
}

Future<void> macosJoinGroup(BuildContext context, WidgetRef ref) async {
  final linkText = await macosPrompt(
    context,
    title: 'Join a group',
    message: 'Paste the invite link an admin sent you.',
    placeholder: 'vbank://join?group=…',
    confirmLabel: 'Continue',
    maxLines: 3,
  );
  if (linkText == null || linkText.trim().isEmpty || !context.mounted) return;

  final result = DeepLinkHandler.parseString(linkText.trim());
  final groupId = result.groupId;
  if (!result.isJoin || groupId == null || result.inviterPeerId == null) {
    await macosToast(context, result.error ?? 'That does not look like a vBank invite', error: true);
    return;
  }
  final identity = ref.read(authProvider).identity;
  if (identity == null) return;

  final passphrase = await macosPrompt(
    context,
    title: 'Group passphrase',
    message: 'Ask the person who invited you.',
    obscure: true,
    confirmLabel: 'Join',
  );
  if (passphrase == null || !context.mounted) return;
  final problem = GroupKeyService.validatePassphrase(passphrase);
  if (problem != null) {
    await macosToast(context, problem, error: true);
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
    final group = await ref.read(syncManagerProvider).joinGroup(
          groupId: groupId,
          groupCid: result.groupCid,
          inviteId: result.inviteId,
          inviteNonceB64: result.inviteNonceB64,
          inviterAddrs: result.inviterAddrs,
          passphrase: passphrase,
          self: self,
          keyPair: keyPair,
        );
    await ref.read(groupListProvider.notifier).refresh();
    ref.read(selectedGroupProvider.notifier).state = group;
    if (context.mounted) {
      await macosToast(
        context,
        group.requireApproval ? 'Join request sent to “${group.name}”' : 'Joined “${group.name}”',
      );
    }
  } on JoinGroupException catch (e) {
    if (context.mounted) await macosToast(context, e.message, error: true);
  } catch (e) {
    if (context.mounted) await macosToast(context, 'Could not join: $e', error: true);
  }
}

Future<void> macosCreateIdentity(BuildContext context, WidgetRef ref) async {
  final name = await macosPrompt(
    context,
    title: 'Welcome to vBank',
    message: 'Enter the name your group knows you by. vBank creates a signing key on this Mac — no '
        'account, no phone number.',
    placeholder: 'Your name',
    confirmLabel: 'Get started',
  );
  if (name == null || name.trim().isEmpty || !context.mounted) return;
  await _run(context, () => ref.read(authProvider.notifier).createIdentity(name.trim()).then((_) {}), null);
}

Future<void> macosCreateBackup(BuildContext context, WidgetRef ref, BackupService service) async {
  final pin1 = TextEditingController();
  final pin2 = TextEditingController();
  final ok = await macosSheet<bool>(
    context,
    title: 'Backup PIN',
    content: (context) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'This PIN protects your signing key and all group keys. At least 6 characters.',
          style: MacosTheme.of(context).typography.body,
        ),
        const SizedBox(height: 14),
        _label(context, 'PIN'),
        MacosTextField(controller: pin1, obscureText: true, autofocus: true),
        const SizedBox(height: 10),
        _label(context, 'Confirm PIN'),
        MacosTextField(controller: pin2, obscureText: true),
      ],
    ),
    actions: (context) => [
      PushButton(
        controlSize: ControlSize.large,
        secondary: true,
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      PushButton(
        controlSize: ControlSize.large,
        onPressed: () => Navigator.pop(context, true),
        child: const Text('Create'),
      ),
    ],
  );
  if (ok != true || !context.mounted) return;

  final problem = BackupService.validatePin(pin1.text) ??
      (pin1.text != pin2.text ? 'PINs do not match' : null);
  if (problem != null) {
    await macosToast(context, problem, error: true);
    return;
  }
  try {
    final id = await service.createFullBackup(passphrase: pin1.text);
    final file = await service.exportBackupToFile(id);
    if (context.mounted) await macosToast(context, 'Backup written to ${file.path}');
  } catch (e) {
    if (context.mounted) await macosToast(context, 'Backup failed: $e', error: true);
  }
}

// -----------------------------------------------------------------------------

Widget _label(BuildContext context, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 4, left: 2),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(text, style: MacosTheme.of(context).typography.caption1),
      ),
    );

Future<void> _run(BuildContext context, Future<void> Function() action, String? success) async {
  try {
    await action();
    if (context.mounted && success != null) await macosToast(context, success);
  } catch (e) {
    if (context.mounted) await macosToast(context, '$e', error: true);
  }
}
