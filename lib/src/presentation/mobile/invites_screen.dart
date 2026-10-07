import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/invite_link.dart';
import '../../app/invite_service.dart';
import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/invites.dart';
import '../../domain/membership.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/invites.dart';
import 'invite_share_screen.dart';

/// A group's invite tickets: list plus creation. The code shown is the
/// invite id; the link (with secret) is assembled by the share layer.
final class MobileInvitesScreen extends ConsumerStatefulWidget {
  /// The group inviting.
  final String groupId;

  /// Clock for liveness; production passes nothing (wall time).
  final DateTime Function()? clock;

  /// Creates the invites screen.
  const MobileInvitesScreen({super.key, required this.groupId, this.clock});

  @override
  ConsumerState<MobileInvitesScreen> createState() => _MobileInvitesState();
}

final class _MobileInvitesState extends ConsumerState<MobileInvitesScreen> {
  /// Last failure, shown inline.
  String? _error;

  /// Creation in flight.
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Invite>> invites =
        ref.watch(inviteListProvider(widget.groupId));
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Invites'),
          trailing: [
            IconButton.ghost(
              key: const ValueKey('new-invite-button'),
              icon: const Icon(LucideIcons.plus),
              onPressed: _saving ? null : _create,
            ),
          ],
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          if (_error != null) ...[
            Text(_error!).small,
            const Gap(12),
          ],
          invites.when(
            loading: () =>
                const Center(child: CircularProgressIndicator()),
            error: (Object error, _) => Text('Error: $error'),
            data: (List<Invite> list) => Column(
              children: [
                if (list.isEmpty)
                  const Text('No invites yet').small.muted,
                for (final Invite i in list)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _reshare(i),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              _codeOf(i),
                              key: ValueKey('invite-${i.id}'),
                            ).medium,
                          ),
                          Text(_stateOf(i)).xSmall.muted,
                        ],
                      ),
                    ),
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
    // The secret exists only here: show the link at once, and keep a
    // copy for re-sharing while the ticket is live.
    final CreatedInvite created = result.value;
    if (created.secret == null) {
      return;
    }
    final String link = InviteLink(
      groupId: g.id,
      groupCid: g.cid ?? '',
      groupTopic: 'vbank/group/${g.id}',
      inviterPeerId: me,
      inviterName: inviterName,
      inviteId: created.invite.id,
      secret: created.secret!,
      nonce: created.invite.nonce,
      expiresAt: created.invite.expiresAt,
    ).encode();
    await InviteLink.storeLink(
      ref.read(appRepositoriesProvider).settings,
      created.invite.id,
      link,
    );
    if (!mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MobileInviteShareScreen(link: link),
      ),
    );
  }

  /// Re-shares a live ticket from its stored link. Spent or expired
  /// tickets clear their link and say so instead.
  Future<void> _reshare(Invite invite) async {
    final settings = ref.read(appRepositoriesProvider).settings;
    final String? link = await InviteLink.loadLink(
      settings,
      invite.id,
    );
    if (link == null || invite.used || invite.isExpiredAt(_now())) {
      await InviteLink.clearLink(settings, invite.id);
      if (mounted) {
        setState(
          () => _error = 'That invite was already used or expired.',
        );
      }
      return;
    }
    if (!mounted) {
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => MobileInviteShareScreen(link: link),
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
