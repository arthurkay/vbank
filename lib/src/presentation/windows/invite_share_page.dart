import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a fresh invite link for sharing. The link carries the one-time
/// secret, so it displays exactly once, right after creation — stored
/// rows cannot rebuild it.
final class WindowsInviteSharePage extends ConsumerStatefulWidget {
  /// The `vbank://join?…` link.
  final String link;

  /// Creates the share page.
  const WindowsInviteSharePage({super.key, required this.link});

  @override
  ConsumerState<WindowsInviteSharePage> createState() =>
      _WindowsInviteSharePageState();
}

final class _WindowsInviteSharePageState
    extends ConsumerState<WindowsInviteSharePage> {
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
  Widget build(BuildContext context) => NavigationView(
    content: ScaffoldPage(
      header: PageHeader(
        leading: IconButton(
          icon: const Icon(FluentIcons.back),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Share invite'),
      ),
      content: ListView(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        children: [
          const Text('Send this link to the new member.'),
          const SizedBox(height: 8),
          const Text(
            'It carries the key to your group — anyone with it can join '
            'until it expires or is used.',
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
          Button(onPressed: _copy, child: const Text('Copy link')),
        ],
      ),
    ),
  );
}
