import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../core/deeplink/deeplink_handler.dart';
import '../../core/deeplink/share_service.dart';
import '../../core/storage/invite_dao.dart';
import '../../providers/auth_provider.dart';
import '../../providers/group_provider.dart';
import '../../providers/ipfs_provider.dart';
import '../../ui/ui.dart';

/// DESIGN_PLAN §16: owner/admin generates a one-use, expiring, signed invite.
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  String? _inviteLink;
  InviteData? _invite;
  bool _isGenerating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _generateInvite();
  }

  Future<void> _generateInvite() async {
    final group = ref.read(selectedGroupProvider);
    final identity = ref.read(authProvider).identity;
    if (group == null || identity == null) return;
    setState(() {
      _isGenerating = true;
      _error = null;
    });
    try {
      final invite = await ref.read(syncManagerProvider).createInvite(group.id);
      final link = DeepLinkHandler.buildJoinLink(
        groupId: group.id,
        inviterPeerId: identity.peerId,
        groupCid: invite.cid,
        inviteId: invite.id,
        inviteNonceB64: base64Encode(invite.nonce!),
        inviterAddrs: ref.read(syncManagerProvider).dialableAddresses,
      );
      if (!mounted) return;
      setState(() {
        _invite = invite;
        _inviteLink = link;
        _isGenerating = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isGenerating = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final group = ref.watch(selectedGroupProvider);
    final identity = ref.watch(authProvider).identity;
    final canInvite = ref.watch(canWriteProvider);
    if (group == null || identity == null) {
      return const AppPage(title: 'Invite', child: EmptyState(icon: LucideIcons.users, title: 'No group selected'));
    }
    final days = _invite == null ? 7 : _invite!.expiresAt.difference(DateTime.now()).inDays + 1;

    return AppPage(
      title: 'Invite Members',
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Invite to ${group.name}', textAlign: TextAlign.center).h3,
            const Gap(8),
            Text(
              'Each invite works once and expires in $days days. Tell the new member the group passphrase in person — it is not in the link.',
              textAlign: TextAlign.center,
            ).muted,
            const Gap(24),
            if (!canInvite)
              const Alert(
                leading: Icon(LucideIcons.lock),
                title: Text('Admins only'),
                content: Text('Only the group owner or an admin can invite members.'),
              )
            else if (_isGenerating)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_error != null) ...[
              Alert.destructive(
                leading: const Icon(LucideIcons.circleAlert),
                title: const Text('Could not create invite'),
                content: Text(_error!),
              ),
              const Gap(12),
              Button.primary(onPressed: _generateInvite, leading: const Icon(LucideIcons.rotateCw), child: const Text('Try again')),
            ] else if (_inviteLink != null) ...[
              Center(
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
                  child: QrImageView(data: _inviteLink!, version: QrVersions.auto, size: 260),
                ),
              ),
              const Gap(24),
              Button.primary(
                onPressed: () => ShareService.shareInviteLink(groupName: group.name, inviteLink: _inviteLink!),
                leading: const Icon(LucideIcons.share2),
                child: const Text('Share Invite Link'),
              ),
              const Gap(12),
              Button.outline(
                onPressed: () async {
                  await ShareService.copyToClipboard(_inviteLink!);
                  if (context.mounted) showMessage(context, 'Invite link copied');
                },
                leading: const Icon(LucideIcons.copy),
                child: const Text('Copy Invite Link'),
              ),
              const Gap(12),
              Button.ghost(onPressed: _generateInvite, leading: const Icon(LucideIcons.rotateCw), child: const Text('New invite')),
            ],
            const Gap(32),
            Panel(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Group info').semiBold,
                  const Gap(12),
                  InfoRow('Members', '${group.memberCount}'),
                  InfoRow('Contribution', fmtMoney(group.config.currency, group.config.contributionAmount)),
                  InfoRow('Frequency', group.config.frequency.name),
                  InfoRow('Join approval', group.requireApproval ? 'Required' : 'Instant'),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
