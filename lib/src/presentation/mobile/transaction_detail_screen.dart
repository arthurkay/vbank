import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/currency.dart';
import '../../domain/group.dart';
import '../../domain/membership.dart';
import '../../domain/transactions.dart';
import '../app_scope.dart';
import '../member/member_actions.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import '../providers/ledger.dart';

/// One ledger entry with its correction flow in shadcn dress: details,
/// reversal state, request form (involved parties) and approve/reject
/// (admins other than the requester).
final class MobileTransactionDetailScreen extends ConsumerStatefulWidget {
  /// The group containing the transaction.
  final String groupId;

  /// The transaction shown.
  final String transactionId;

  /// Creates the screen.
  const MobileTransactionDetailScreen({
    super.key,
    required this.groupId,
    required this.transactionId,
  });

  @override
  ConsumerState<MobileTransactionDetailScreen> createState() =>
      _MobileTransactionDetailScreenState();
}

final class _MobileTransactionDetailScreenState
    extends ConsumerState<MobileTransactionDetailScreen> {
  final TextEditingController _reason = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _requesting = false;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  /// Files a correction request, then refreshes the list.
  Future<void> _request() async {
    final String? me = ref.read(authProvider).identity?.peerId;
    if (me == null) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    if (_reason.text.trim().isEmpty) {
      setState(() => _error = 'Give a reason for the correction.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<TransactionReversal> result = await ref
        .read(appServicesProvider)
        .governance
        .requestReversal(
          groupId: widget.groupId,
          actingPeerId: me,
          transactionId: widget.transactionId,
          reason: _reason.text,
        );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _busy = false;
        _error = _explain(result.failure);
      });
      return;
    }
    ref.invalidate(reversalsProvider(widget.groupId));
    setState(() {
      _busy = false;
      _requesting = false;
      _reason.clear();
    });
  }

  /// Decides a pending request, then refreshes the list.
  Future<void> _decide(TransactionReversal reversal, bool approve) async {
    final String? me = ref.read(authProvider).identity?.peerId;
    if (me == null) {
      setState(() => _error = 'Sign in first.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    final Result<TransactionReversal> result = await ref
        .read(appServicesProvider)
        .governance
        .decideReversal(
          groupId: widget.groupId,
          actingPeerId: me,
          reversalId: reversal.id,
          approve: approve,
        );
    if (!mounted) {
      return;
    }
    if (result.isErr) {
      setState(() {
        _busy = false;
        _error = _explain(result.failure);
      });
      return;
    }
    ref.invalidate(reversalsProvider(widget.groupId));
    setState(() => _busy = false);
  }

  /// Machine failure codes to human words.
  static String _explain(Failure failure) => switch (failure) {
    PermissionFailure(:final action) => 'Not allowed ($action).',
    ValidationFailure(:final reason) => 'Check the request ($reason).',
    NotFoundFailure(:final subject) => 'Missing $subject.',
    ConflictFailure(:final subject) => 'Conflict on $subject.',
    NetworkFailure() => 'No connection.',
    IntegrityFailure(:final subject) => 'Rejected $subject.',
    StorageFailure() => 'Storage failed.',
  };

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Transaction>> txs = ref.watch(
      transactionsProvider(widget.groupId),
    );
    final AsyncValue<Group?> group = ref.watch(selectedGroupProvider);
    final String? me = ref.watch(authProvider).identity?.peerId;
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Transaction'),
        ),
      ],
      child: txs.when(
        loading: () =>
            const Center(child: CircularProgressIndicator()),
        error: (Object error, _) => Center(child: Text('Error: $error')),
        data: (List<Transaction> list) {
          Transaction? tx;
          for (final Transaction t in list) {
            if (t.id == widget.transactionId) {
              tx = t;
            }
          }
          if (tx == null) {
            return Center(
              child: Text('No longer on record.').small.muted,
            );
          }
          final Transaction shown = tx;
          final Group? g = group.valueOrNull;
          final String currency = g?.config.currency ?? 'ZMW';
          final String money =
              CurrencyConfig.supported[currency]?.format(shown.amount) ??
              '${shown.amount} $currency';
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(shown.type.name).xLarge.bold,
              const Gap(8),
              Text(money).large,
              const Gap(8),
              Text('Status: ${shown.status.name}').small.muted,
              if (shown.note != null && shown.note!.isNotEmpty) ...[
                const Gap(8),
                Text(shown.note!).small,
              ],
              const Gap(20),
              _ReversalSection(
                groupId: widget.groupId,
                transaction: shown,
                myPeerId: me,
                myRole: g == null ? null : myRole(g, me),
                requesting: _requesting,
                busy: _busy,
                error: _error,
                reason: _reason,
                onToggleRequest: () => setState(() {
                  _requesting = !_requesting;
                  _error = null;
                }),
                onRequest: _saveRequest,
                onDecide: _decide,
              ),
            ],
          );
        },
      ),
    );
  }

  /// Wraps [_request] for the section callback.
  Future<void> _saveRequest() => _request();
}

/// Correction state, request form and pending decisions.
final class _ReversalSection extends StatelessWidget {
  /// The group both belong to.
  final String groupId;

  /// The transaction under correction.
  final Transaction transaction;

  /// This device's peer id, if signed in.
  final String? myPeerId;

  /// This device's role, if a member.
  final MemberRole? myRole;

  /// Whether the request form is open.
  final bool requesting;

  /// A request/decision in flight.
  final bool busy;

  /// Last failure, shown inline.
  final String? error;

  /// Reason input.
  final TextEditingController reason;

  /// Toggles the request form.
  final VoidCallback onToggleRequest;

  /// Files the request.
  final Future<void> Function() onRequest;

  /// Decides a pending request.
  final Future<void> Function(TransactionReversal reversal, bool approve)
  onDecide;

  /// Creates the section.
  const _ReversalSection({
    required this.groupId,
    required this.transaction,
    required this.myPeerId,
    required this.myRole,
    required this.requesting,
    required this.busy,
    required this.error,
    required this.reason,
    required this.onToggleRequest,
    required this.onRequest,
    required this.onDecide,
  });

  @override
  Widget build(BuildContext context) => Consumer(
    builder: (BuildContext context, WidgetRef ref, _) {
      final AsyncValue<List<TransactionReversal>> reversals = ref.watch(
        reversalsProvider(groupId),
      );
      return reversals.when(
        loading: () => const SizedBox.shrink(),
        error: (_, _) => const SizedBox.shrink(),
        data: (List<TransactionReversal> all) {
          final List<TransactionReversal> mine = [
            for (final TransactionReversal r in all)
              if (r.originalTransactionId == transaction.id) r,
          ];
          TransactionReversal? pending;
          for (final TransactionReversal r in mine) {
            if (r.status == ReversalStatus.pending) {
              pending = r;
            }
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Corrections').small.semiBold.muted,
              const Gap(8),
              if (transaction.status == TransactionStatus.reversed)
                const Text('Voided by an approved correction.').small
              else if (pending != null)
                _PendingCard(
                  reversal: pending,
                  myPeerId: myPeerId,
                  myRole: myRole,
                  busy: busy,
                  onDecide: onDecide,
                )
              else if (requesting) ...[
                TextField(
                  controller: reason,
                  placeholder: const Text('Why is it wrong?'),
                  onSubmitted: (_) => onRequest(),
                ),
                const Gap(8),
                PrimaryButton(
                  onPressed: busy ? null : onRequest,
                  child: Text(busy ? 'Sending…' : 'Request correction'),
                ),
              ] else ...[
                OutlineButton(
                  onPressed: onToggleRequest,
                  child: const Text('Request correction'),
                ),
              ],
              if (error != null) ...[
                const Gap(8),
                Text(error!).small,
              ],
              for (final TransactionReversal r in mine)
                if (r.status != ReversalStatus.pending)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      '${r.status.name}: ${r.reason}',
                    ).small.muted,
                  ),
            ],
          );
        },
      );
    },
  );
}

/// A pending request with approve/reject for eligible deciders.
final class _PendingCard extends StatelessWidget {
  /// The pending request.
  final TransactionReversal reversal;

  /// This device's peer id.
  final String? myPeerId;

  /// This device's role.
  final MemberRole? myRole;

  /// A decision in flight.
  final bool busy;

  /// Decides the request.
  final Future<void> Function(TransactionReversal reversal, bool approve)
  onDecide;

  /// Creates the card.
  const _PendingCard({
    required this.reversal,
    required this.myPeerId,
    required this.myRole,
    required this.busy,
    required this.onDecide,
  });

  @override
  Widget build(BuildContext context) {
    final MemberRole? role = myRole;
    final bool canDecide =
        role != null &&
        canWrite(role) &&
        reversal.requestedByPeerId != myPeerId;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Pending: ${reversal.reason}').small,
            if (canDecide) ...[
              const Gap(8),
              Row(
                children: [
                  PrimaryButton(
                    onPressed: busy
                        ? null
                        : () => onDecide(reversal, true),
                    child: const Text('Approve'),
                  ),
                  const Gap(8),
                  OutlineButton(
                    onPressed: busy
                        ? null
                        : () => onDecide(reversal, false),
                    child: const Text('Reject'),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
