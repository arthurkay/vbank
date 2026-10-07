import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../app/invite_link.dart';
import '../../app/invite_service.dart';
import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/invites.dart';
import '../../domain/membership.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/invites.dart';
import 'invite_share_page.dart';

/// A group's invite tickets on Linux.
final class LinuxInvitesPage extends ConsumerStatefulWidget {
  /// The group inviting.
  final String groupId;

  /// Clock for liveness; production passes nothing (wall time).
  final DateTime Function()? clock;

  /// Creates the invites page.
  const LinuxInvitesPage({super.key, required this.groupId, this.clock});

  @override
  ConsumerState<LinuxInvitesPage> createState() => _LinuxInvitesState();
}

final class _LinuxInvitesState extends ConsumerState<LinuxInvitesPage> {
  /// Last failure, shown inline.
  String? _error;

  /// Creation in flight.
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Invite>> invites =
        ref.watch(inviteListProvider(widget.groupId));
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Invites'),
        actions: [
          IconButton(
            key: const ValueKey('new-invite-button'),
            tooltip: 'New invite',
            icon: const Icon(YaruIcons.plus),
            onPressed: _saving ? null : _create,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          if (_error != null) ...[
            Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
          ],
          invites.when(
            loading: () =>
                const Center(child: YaruCircularProgressIndicator()),
            error: (Object error, _) => Text('Error: $error'),
            data: (List<Invite> list) => Column(
              children: [
                if (list.isEmpty) const Text('No invites yet'),
                for (final Invite i in list)
                  YaruListTile(
                    title: Text(
                      _codeOf(i),
                      key: ValueKey('invite-${i.id}'),
                    ),
                    trailing: Text(_stateOf(i)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Short display code for a ticket id.
  static String _codeOf(Invite invite) => invite.id.length <= 8
      ? invite.id
      : '${invite.id.substring(0, 8)}…';

  /// Clock in force: the injected one, else wall time.
  DateTime _now() {
    final DateTime Function()? clock = widget.clock;
    return (clock == null ? DateTime.now() : clock()).toUtc();
  }

  /// Human ticket state.
  String _stateOf(Invite invite) {
    if (invite.used) {
      return 'used';
    }
    if (invite.isExpiredAt(_now())) {
      return 'expired';
    }
    return 'live';
  }

  /// Creates a signed invite through the service.
  Future<void> _create() async {
    final groupResult = await ref
        .read(appRepositoriesProvider)
        .groups
        .findById(widget.groupId);
    final String? me = ref.read(authProvider).identity?.peerId;
    if (groupResult.isErr || me == null) {
      setState(() => _error = 'Open a group first.');
      return;
    }
    final Group g = groupResult.value;
    Member? inviter;
    for (final Member m in g.members) {
      if (m.peerId == me) {
        inviter = m;
      }
    }
    if (inviter == null || !canWrite(inviter.role)) {
      setState(() => _error = 'Not allowed (notWriter).');
      return;
    }
    // Captured before the first await: promotion does not survive it.
    final String inviterName = inviter.name;
    final key = await ref.read(appServicesProvider).keys.getKey(g.id);
    if (key == null) {
      setState(() => _error = 'Enter the group passphrase first.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    final result =
        await ref.read(appServicesProvider).invites.createInvite(
              groupId: g.id,
              groupCid: g.cid ?? '',
              groupTopic: 'vbank/group/${g.id}',
              inviterPeerId: me,
              inviterName: inviterName,
              groupKey: key,
            );
    if (!mounted) {
      return;
    }
    setState(() => _saving = false);
    if (result.isErr) {
      setState(() => _error = _explain(result.failure));
      return;
    }
    // The secret exists only here: show the link at once, because the
    // stored row can never rebuild it.
    final CreatedInvite created = result.value;
    if (created.secret == null) {
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => LinuxInviteSharePage(
          link: InviteLink(
            groupId: g.id,
            groupCid: g.cid ?? '',
            groupTopic: 'vbank/group/${g.id}',
            inviterPeerId: me,
            inviterName: inviterName,
            inviteId: created.invite.id,
            secret: created.secret!,
            nonce: created.invite.nonce,
            expiresAt: created.invite.expiresAt,
          ).encode(),
        ),
      ),
    );
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
