import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart' show SelectableText;
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:macos_ui/macos_ui.dart';
import 'package:share_plus/share_plus.dart';

/// Shows a fresh invite link for sharing. The link carries the one-time
/// secret, so it displays exactly once, right after creation — stored
/// rows cannot rebuild it.
final class MacosInviteSharePage extends ConsumerStatefulWidget {
  /// The `vbank://join?…` link.
  final String link;

  /// Creates the share page.
  const MacosInviteSharePage({super.key, required this.link});

  @override
  ConsumerState<MacosInviteSharePage> createState() =>
      _MacosInviteSharePageState();
}

final class _MacosInviteSharePageState
    extends ConsumerState<MacosInviteSharePage> {
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
  Widget build(BuildContext context) => MacosWindow(
    child: MacosScaffold(
      toolBar: ToolBar(
        leading: MacosBackButton(
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Share invite'),
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
            children: [
              const Text('Send this link to the new member.'),
              const SizedBox(height: 8),
              const Text(
                'It carries the key to your group — anyone with it can '
                'join until it expires or is used.',
              ),
              const SizedBox(height: 16),
              Center(
                // White behind and around the code: the light modules
                // vanish on dark pages otherwise, and scanners need the
                // quiet zone.
                child: ColoredBox(
                  color: const Color(0xFFFFFFFF),
                  child: QrImageView(
                    data: widget.link,
                    size: 220,
                    backgroundColor: const Color(0xFFFFFFFF),
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
              PushButton(
                controlSize: ControlSize.large,
                onPressed: _share,
                child: const Text('Share…'),
              ),
              const SizedBox(height: 12),
              PushButton(
                controlSize: ControlSize.large,
                secondary: true,
                onPressed: _copy,
                child: const Text('Copy link'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
