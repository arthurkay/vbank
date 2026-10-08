import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:yaru/yaru.dart';

/// Shows a fresh invite link for sharing. The link carries the one-time
/// secret, so it displays exactly once, right after creation — stored
/// rows cannot rebuild it.
final class LinuxInviteSharePage extends ConsumerStatefulWidget {
  /// The `vbank://join?…` link.
  final String link;

  /// Creates the share page.
  const LinuxInviteSharePage({super.key, required this.link});

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
  Widget build(BuildContext context) => YaruDetailPage(
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
              data: widget.link,
              size: 220,
              backgroundColor: Colors.white,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SelectableText(widget.link),
        const SizedBox(height: 16),
        if (_copied) ...[
          const Text('Copied to clipboard.'),
          const SizedBox(height: 12),
        ],
        if (_error != null) ...[
          Text(_error!),
          const SizedBox(height: 12),
        ],
        FilledButton(onPressed: _share, child: const Text('Share…')),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: _copy, child: const Text('Copy link')),
      ],
    ),
  );
}
