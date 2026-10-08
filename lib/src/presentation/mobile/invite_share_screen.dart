import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a fresh invite link for sharing. The link carries the one-time
/// secret, so it displays exactly once, right after creation — stored
/// rows cannot rebuild it.
final class MobileInviteShareScreen extends ConsumerStatefulWidget {
  /// The `vbank://join?…` link.
  final String link;

  /// Creates the share screen.
  const MobileInviteShareScreen({super.key, required this.link});

  @override
  ConsumerState<MobileInviteShareScreen> createState() =>
      _MobileInviteShareScreenState();
}

final class _MobileInviteShareScreenState
    extends ConsumerState<MobileInviteShareScreen> {
  /// Copy confirmation, shown inline.
  bool _copied = false;

  /// Share failure, shown inline (copy still works).
  String? _error;

  /// Copies the link to the clipboard.
  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.link));
    if (mounted) {
      setState(() {
        _copied = true;
        _error = null;
      });
    }
  }

  /// Opens the system share sheet. Falls back to copy on platforms
  /// without one.
  Future<void> _share() async {
    setState(() => _error = null);
    try {
      await Share.share(widget.link, subject: 'vBank invite');
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() => _error = 'Sharing is unavailable — copy the link.');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    headers: [
      AppBar(
        leading: [
          IconButton.ghost(
            icon: const Icon(LucideIcons.arrowLeft),
            onPressed: () => Navigator.pop(context),
          ),
        ],
        title: const Text('Share invite'),
      ),
    ],
    child: ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Send this link to the new member.').small,
        const Gap(8),
        Text(
          'It carries the key to your group — anyone with it can join '
          'until it expires or is used.',
        ).small.muted,
        const Gap(16),
        Center(
          child: QrImageView(data: widget.link, size: 220),
        ),
        const Gap(16),
        SelectableText(widget.link).small,
        const Gap(16),
        if (_copied) ...[
          const Text('Copied to clipboard.').small,
          const Gap(12),
        ],
        if (_error != null) ...[
          Text(_error!).small,
          const Gap(12),
        ],
        PrimaryButton(onPressed: _share, child: const Text('Share…')),
        const Gap(12),
        OutlineButton(onPressed: _copy, child: const Text('Copy link')),
      ],
    ),
  );
}
