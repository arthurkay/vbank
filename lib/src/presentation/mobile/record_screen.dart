import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../app_scope.dart';
import '../member/member_actions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// Records one movement: treasurer picks a kind, a member and an amount.
/// Plain members see the form too but the service refuses them with an
/// explanation (read-only roles must understand why).
final class MobileRecordScreen extends ConsumerStatefulWidget {
  /// The group receiving the record.
  final String groupId;

  /// Creates the record screen.
  const MobileRecordScreen({super.key, required this.groupId});

  @override
  ConsumerState<MobileRecordScreen> createState() => _MobileRecordState();
}

final class _MobileRecordState extends ConsumerState<MobileRecordScreen> {
  /// Kinds a treasurer can record by hand (loans and repayments flow
  /// through the loan screens so schedules stay consistent).
  static const List<TransactionType> kinds = [
    TransactionType.contribution,
    TransactionType.withdrawal,
    TransactionType.penalty,
    TransactionType.fee,
  ];

  /// Selected kind.
  TransactionType _type = TransactionType.contribution;

  /// Selected member peer id.
  String? _memberId;

  /// Amount input.
  final TextEditingController _amount = TextEditingController();

  /// Memo input.
  final TextEditingController _note = TextEditingController();

  /// Last failure, shown inline.
  String? _error;

  /// Save in flight.
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final Group? g = group.valueOrNull;
    if (!canRecord(g, ref.watch(authProvider).identity?.peerId)) {
      return Scaffold(
        headers: [
          AppBar(
            leading: [
              IconButton.ghost(
                icon: const Icon(LucideIcons.arrowLeft),
                onPressed: () => Navigator.pop(context),
              ),
            ],
            title: const Text('Record transaction'),
          ),
        ],
        child: const Center(
          child: Text('Only owners and admins record transactions.'),
        ),
      );
    }
    final List<Member> members = [
      for (final Member m in g?.members ?? const <Member>[])
        if (m.status == MemberStatus.active) m,
    ];
    _memberId ??= members.isNotEmpty ? members.first.peerId : null;
    Member? selected;
    for (final Member m in members) {
      if (m.peerId == _memberId) {
        selected = m;
      }
    }
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Record transaction'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            _direction(_type, selected?.name ?? 'a member'),
          ).small.semiBold.muted,
          const Gap(4),
          if (_type == TransactionType.contribution && g != null)
            Text(
              'Expected ${g.config.contributionAmount} '
              '${g.config.currency} ${g.config.frequency.name}.',
            ).small.muted,
          const Gap(12),
          Text('Kind').small.semiBold.muted,
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final TransactionType kind in kinds)
                _type == kind
                    ? PrimaryButton(
                        onPressed: () => setState(() => _type = kind),
                        child: Text(kind.name),
                      )
                    : OutlineButton(
                        onPressed: () => setState(() => _type = kind),
                        child: Text(kind.name),
                      ),
            ],
          ),
          const Gap(16),
          Text('Member').small.semiBold.muted,
          const Gap(8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final Member m in members)
                _memberId == m.peerId
                    ? PrimaryButton(
                        onPressed: () => setState(() => _memberId = m.peerId),
                        child: Text(m.name),
                      )
                    : OutlineButton(
                        onPressed: () => setState(() => _memberId = m.peerId),
                        child: Text(m.name),
                      ),
            ],
          ),
          const Gap(16),
          Text('Amount').small.semiBold.muted,
          const Gap(8),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            placeholder: const Text('0.00'),
          ),
          const Gap(16),
          Text('Note (optional)').small.semiBold.muted,
          const Gap(8),
          TextField(controller: _note, placeholder: const Text('Memo')),
          const Gap(20),
          if (_error != null) ...[Text(_error!).small, const Gap(12)],
          PrimaryButton(
            onPressed: _saving ? null : () => _save(g),
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }

  /// Who pays whom for the current kind and member, in plain words.
  static String _direction(TransactionType type, String name) => switch (type) {
    TransactionType.contribution => '$name pays into the group fund',
    TransactionType.withdrawal => 'Group fund pays out to $name',
    TransactionType.penalty => '$name owes a penalty to the fund',
    TransactionType.fee => '$name pays a group fee',
    _ => '$name ↔ group fund',
  };

  /// Validates locally, records through the service, closes on success.
  Future<void> _save(Group? group) async {
    final String? memberId = _memberId;
    final double? amount = double.tryParse(_amount.text.trim());
    final String? identity = ref.read(authProvider).identity?.peerId;
    if (group == null || memberId == null || identity == null) {
      setState(() => _error = 'Pick a member first.');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount above zero.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final bool out = _type == TransactionType.withdrawal;
    final transactions = ref.read(appServicesProvider).transactions;
    final result = await transactions.createTransaction(
      groupId: group.id,
      authorPeerId: identity,
      fromPeerId: out ? 'group' : memberId,
      toPeerId: out ? memberId : 'group',
      type: _type,
      amount: amount,
      currency: group.config.currency,
      note: _note.text.trim().isEmpty ? null : _note.text.trim(),
    );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _saving = false;
        _error = _explain(result.failure);
      });
      return;
    }
    Navigator.pop(context);
  }

  /// Machine failure codes to human words.
  static String _explain(Failure failure) => switch (failure) {
    PermissionFailure(:final action) => 'Not allowed ($action).',
    ValidationFailure(:final reason) => 'Check the form ($reason).',
    NotFoundFailure(:final subject) => 'Missing $subject.',
    ConflictFailure(:final subject) => 'Conflict on $subject.',
    NetworkFailure() => 'No connection.',
    IntegrityFailure(:final subject) => 'Rejected $subject.',
    StorageFailure() => 'Storage failed.',
  };
}
