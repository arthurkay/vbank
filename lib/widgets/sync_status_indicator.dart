import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../core/ipfs/ipfs_service.dart';
import '../core/ipfs/sync_manager.dart';
import '../ui/ui.dart' show VBankTheme;

enum SyncStatus { online, syncing, connecting, offline }

/// Derives the user-facing status from the IPFS node state and sync state.
SyncStatus syncStatusFrom(IpfsNodeState node, SyncState sync) {
  if (sync == SyncState.syncing) {
    return node == IpfsNodeState.running ? SyncStatus.syncing : SyncStatus.connecting;
  }
  switch (node) {
    case IpfsNodeState.running:
      return SyncStatus.online;
    case IpfsNodeState.starting:
      return SyncStatus.connecting;
    case IpfsNodeState.stopping:
    case IpfsNodeState.stopped:
      return SyncStatus.offline;
  }
}

class SyncStatusIndicator extends StatelessWidget {
  final SyncStatus status;
  final VoidCallback? onTap;
  const SyncStatusIndicator({super.key, required this.status, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon, label) = switch (status) {
      SyncStatus.online => (VBankTheme.success, LucideIcons.cloud, 'Online'),
      SyncStatus.syncing => (VBankTheme.warning(context), LucideIcons.refreshCw, 'Syncing...'),
      SyncStatus.connecting => (VBankTheme.warning(context), LucideIcons.cloud, 'Connecting...'),
      SyncStatus.offline => (scheme.mutedForeground, LucideIcons.cloudOff, 'Offline'),
    };
    return Button.ghost(
      onPressed: onTap,
      leading: Icon(icon, size: 16, color: color),
      child: Text(label, style: TextStyle(color: color)).xSmall,
    );
  }
}
