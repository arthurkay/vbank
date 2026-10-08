import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/invite_link.dart';

/// Scans a member's invite QR and returns the link. Anything that is
/// not a vBank invite is ignored, so stray codes never close the
/// scanner. Camera only: desktop joins paste links instead.
final class MobileScanScreen extends ConsumerStatefulWidget {
  /// Creates the scan screen.
  const MobileScanScreen({super.key});

  @override
  ConsumerState<MobileScanScreen> createState() => _MobileScanScreenState();
}

final class _MobileScanScreenState
    extends ConsumerState<MobileScanScreen> {
  /// Set on the first vBank code so repeats do not pop twice.
  bool _done = false;

  /// Returns the first vBank invite link in [capture], if any.
  void _onDetect(BarcodeCapture capture) {
    if (_done) {
      return;
    }
    for (final barcode in capture.barcodes) {
      final String? raw = barcode.rawValue;
      if (raw != null && raw.startsWith(InviteLink.prefix)) {
        _done = true;
        if (mounted) {
          Navigator.pop(context, raw);
        }
        return;
      }
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
        title: const Text('Scan invite'),
      ),
    ],
    child: MobileScanner(onDetect: _onDetect),
  );
}
