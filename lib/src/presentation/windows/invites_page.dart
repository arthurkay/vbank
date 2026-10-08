import 'dart:async';

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/invite_link.dart';
import '../../app/invite_service.dart';
import '../../domain/core/failure.dart';
import '../../domain/group.dart';
import '../../domain/invites.dart';
import '../../domain/membership.dart';
import '../app_scope.dart';
import '../providers/auth.dart';
import '../providers/invites.dart';
import '../providers/sync.dart';
import 'invite_share_page.dart';

/// A group's invite tickets on Windows.
final class WindowsInvitesPage extends ConsumerStatefulWidget {
  /// The group inviting.
  final String groupId;

  /// Clock for liveness; production passes nothing (wall time).
  final DateTime Function()? clock;

  /// Creates the invites page.
  const WindowsInvitesPage({super.key, required this.groupId, this.clock});

  @override
  ConsumerState<WindowsInvitesPage> createState() => _WindowsInvitesState();
}

final class _WindowsInvitesState extends ConsumerState<WindowsInvitesPage> {
  /// Last failure, shown inline.
  String? _error;

  /// Creation in flight.
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final AsyncValue<List<Invite>> invites =
        ref.watch(inviteListProvider(widget.groupId));
    return NavigationView(
      titleBar: const TitleBar(title: Text('Invites')),
      content: ScaffoldPage(
        header: PageHeader(
          leading: IconButton(
            icon: const Icon(FluentIcons.back),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Invites'),
          commandBar: CommandBar(
            mainAxisAlignment: MainAxisAlignment.end,
            primaryItems: [
              CommandBarButton(
                key: const ValueKey('new-invite-button'),
                icon: const Icon(FluentIcons.add),
                label: const Text('New'),
                onPressed: _saving ? null : _create,
              ),
            ],
          ),
        ),
        content: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
          children: [
            if (_error != null) ...[
              Text(_error!),
              const SizedBox(height: 12),
            ],
            invites.when(
              loading: () => const Center(child: ProgressRing()),
              error: (Object error, _) => Center(child: Text('Error: $error')),
              data: (List<Invite> list) => Column(
                children: [
                  if (list.isEmpty) const Text('No invites yet'),
                  for (final Invite i in list)
                    ListTile(
                      onPressed: () => _reshare(i),
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
              inviterName: inviter.name,
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
    // Push the fresh snapshot (with this invite's wrap) to the relays
    // now, so the link works as soon as it is shared — without waiting
    // for the next periodic round. Best effort: failures surface there.
    final sync = ref.read(syncCoordinatorProvider);
    if (sync != null) {
      unawaited(sync.synchronizeNow().then((_) {}, onError: (_) {}));
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
      inviterPeerId: me,
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
      FluentPageRoute<void>(
        builder: (_) => WindowsInviteSharePage(
          link: link,
          groupId: widget.groupId,
        ),
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
      FluentPageRoute<void>(
        builder: (_) => WindowsInviteSharePage(
          link: link,
          groupId: widget.groupId,
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
