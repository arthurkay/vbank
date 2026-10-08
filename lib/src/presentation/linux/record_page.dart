import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../app_scope.dart';
import '../member/member_actions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import 'group_detail_page.dart' show authorOf;

/// Records one movement: kind, member, amount, memo.
final class LinuxRecordPage extends ConsumerStatefulWidget {
  /// The group receiving the record.
  final String groupId;

  /// Creates the page.
  const LinuxRecordPage({super.key, required this.groupId});

  @override
  ConsumerState<LinuxRecordPage> createState() => _LinuxRecordState();
}

final class _LinuxRecordState extends ConsumerState<LinuxRecordPage> {
  /// Hand-recorded kinds (loans flow through loan screens).
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
    final Group? group = ref.watch(selectedGroupProvider).valueOrNull;
    if (!canRecord(group, ref.watch(authProvider).identity?.peerId)) {
      return YaruDetailPage(
        appBar: AppBar(
          leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
          title: const Text('Record transaction'),
        ),
        body: const Center(
          child: Text('Only owners and admins record transactions.'),
        ),
      );
    }
    final List<Member> members = [
      for (final Member m in group?.members ?? const <Member>[])
        if (m.status == MemberStatus.active) m,
    ];
    _memberId ??= members.isNotEmpty ? members.first.peerId : null;
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Record transaction'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const Text('Kind'),
          DropdownButton<TransactionType>(
            value: _type,
            items: [
              for (final TransactionType kind in kinds)
                DropdownMenuItem(value: kind, child: Text(kind.name)),
            ],
            onChanged: (TransactionType? kind) {
              if (kind != null) {
                setState(() => _type = kind);
              }
            },
          ),
          const SizedBox(height: 12),
          const Text('Member'),
          DropdownButton<String>(
            value: _memberId,
            items: [
              for (final Member m in members)
                DropdownMenuItem(value: m.peerId, child: Text(m.name)),
            ],
            onChanged: (String? peerId) {
              if (peerId != null) {
                setState(() => _memberId = peerId);
              }
            },
          ),
          const SizedBox(height: 12),
          const Text('Amount'),
          TextField(
            controller: _amount,
            keyboardType: const TextInputType.numberWithOptions(
              decimal: true,
            ),
            decoration: const InputDecoration(hintText: '0.00'),
          ),
          const SizedBox(height: 12),
          const Text('Note (optional)'),
          TextField(
            controller: _note,
            decoration: const InputDecoration(hintText: 'Memo'),
          ),
          const SizedBox(height: 20),
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: _saving ? null : () => _save(group),
            child: Text(_saving ? 'Saving…' : 'Save'),
          ),
        ],
      ),
    );
  }

  /// Validates locally, records through the service, closes on success.
  Future<void> _save(Group? group) async {
    final String? memberId = _memberId;
    final double? amount = double.tryParse(_amount.text.trim());
    final String? identity = authorOf(ref);
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
