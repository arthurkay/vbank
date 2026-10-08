import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yaru/yaru.dart';

import '../../app/invite_link.dart';
import '../../domain/group.dart';
import '../providers/groups.dart';

/// Shows a fresh invite link for sharing. The link carries the one-time
/// secret, so it displays exactly once, right after creation — stored
/// rows cannot rebuild it.
///
/// The displayed link tracks the group's snapshot: when a round lands a
/// newer snapshot, the page re-encodes around its CID, so a copied
/// link never points at a snapshot the relay does not have yet.
final class LinuxInviteSharePage extends ConsumerStatefulWidget {
  /// The `vbank://join?…` link, as built at creation.
  final String link;

  /// The group the link opens, watched for snapshot changes.
  final String groupId;

  /// Creates the share page.
  const LinuxInviteSharePage({
    super.key,
    required this.link,
    required this.groupId,
  });

  @override
  ConsumerState<LinuxInviteSharePage> createState() =>
      _LinuxInviteSharePageState();
}

final class _LinuxInviteSharePageState
    extends ConsumerState<LinuxInviteSharePage> {
  /// Copy confirmation, shown inline.
  bool _copied = false;

  /// Share failure, shown inline (copy still works).
  String? _error;

  /// The link to show, share and copy: the creation link re-encoded
  /// around the group's current snapshot CID, so it never points at a
  /// snapshot the relay does not have yet. Falls back to the creation
  /// link when the group (or its CID) is unavailable.
  String _displayLink(Group? group) {
    final InviteLink? parts = InviteLink.tryParse(widget.link);
    final String? cid = group?.cid;
    if (parts == null || cid == null || cid.isEmpty || cid == parts.groupCid) {
      return widget.link;
    }
    return InviteLink(
      groupId: parts.groupId,
      groupCid: cid,
      inviterPeerId: parts.inviterPeerId,
      inviteId: parts.inviteId,
      secret: parts.secret,
      nonce: parts.nonce,
      expiresAt: parts.expiresAt,
    ).encode();
  }

  /// Copies the link to the clipboard.
  Future<void> _copy(String link) async {
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) {
      setState(() {
        _copied = true;
        _error = null;
      });
    }
  }

  /// Opens the system share sheet. Falls back to copy on platforms
  /// without one.
  Future<void> _share(String link) async {
    setState(() => _error = null);
    try {
      await Share.share(link, subject: 'vBank invite');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Sharing is unavailable — copy the link.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Group> groups =
        ref.watch(groupListProvider).valueOrNull ?? const [];
    Group? group;
    for (final Group g in groups) {
      if (g.id == widget.groupId) {
        group = g;
      }
    }
    final String link = _displayLink(group);
    return YaruDetailPage(
      appBar: AppBar(
        leading: YaruBackButton(onPressed: () => Navigator.pop(context)),
        title: const Text('Share invite'),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const Text('Send this link to the new member.'),
          const SizedBox(height: 8),
          const Text(
            'It carries the key to your group — anyone with it can join '
            'until it expires or is used.',
          ),
          const SizedBox(height: 16),
          Center(
            // White behind and around the code: the light modules vanish
            // on dark pages otherwise, and scanners need the quiet zone.
            child: ColoredBox(
              color: Colors.white,
              child: QrImageView(
                data: link,
                size: 220,
                backgroundColor: Colors.white,
              ),
            ),
          ),
          const SizedBox(height: 16),
          SelectableText(link),
          const SizedBox(height: 16),
          if (_copied) ...[
            const Text('Copied to clipboard.'),
            const SizedBox(height: 12),
          ],
          if (_error != null) ...[
            Text(_error!),
            const SizedBox(height: 12),
          ],
          FilledButton(
            onPressed: () => _share(link),
            child: const Text('Share…'),
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            onPressed: () => _copy(link),
            child: const Text('Copy link'),
          ),
        ],
      ),
    );
  }
}
