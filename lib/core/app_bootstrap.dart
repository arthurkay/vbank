/// Start-up work every shell needs, whatever its design system.
///
/// Loading the identity, handing it to the sync manager, bringing the IPFS node
/// up, turning inbound changes into notifications and handling `vbank://` deep
/// links are all platform-neutral — only the widgets above differ. Each shell
/// wraps itself in [AppBootstrap] so none of it can be forgotten (that omission
/// is exactly what left the first Linux build stuck on its spinner).
library;

import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart' show SimpleKeyPair;
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../providers/ipfs_provider.dart';
import '../providers/notification_provider.dart';
import 'app_platform.dart';
import 'deeplink/deeplink_handler.dart';
import '../services/cloud_backup_service.dart';
import 'ipfs/sync_manager.dart' show SyncChange, SyncChangeType;
import 'notifications/notification_service.dart';

/// What a tapped notification points at.
class NotificationTarget {
  final SyncChangeType type;
  final String groupId;
  final String? recordId;
  const NotificationTarget({required this.type, required this.groupId, this.recordId});

  String encode() => jsonEncode({'type': type.name, 'groupId': groupId, 'recordId': recordId});

  static NotificationTarget? decode(String payload) {
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      final type = SyncChangeType.values.where((t) => t.name == m['type']).firstOrNull;
      final groupId = m['groupId'] as String?;
      if (type == null || groupId == null) return null;
      return NotificationTarget(type: type, groupId: groupId, recordId: m['recordId'] as String?);
    } catch (_) {
      return null; // older payloads were a bare group id
    }
  }
}

class AppBootstrap extends ConsumerStatefulWidget {
  final Widget child;

  /// Called for every deep link, including the one that cold-started the app.
  /// Desktop shells that have nowhere to route a link can leave this null.
  final void Function(DeepLinkResult link)? onDeepLink;

  /// Called when the user taps one of our notifications (including the tap
  /// that cold-started the app).
  final void Function(NotificationTarget target)? onNotificationTap;

  const AppBootstrap({super.key, required this.child, this.onDeepLink, this.onNotificationTap});

  @override
  ConsumerState<AppBootstrap> createState() => _AppBootstrapState();
}

class _AppBootstrapState extends ConsumerState<AppBootstrap> with WidgetsBindingObserver {
  final _deepLinkHandler = DeepLinkHandler();
  StreamSubscription<DeepLinkResult>? _deepLinkSub;
  StreamSubscription<SyncChange>? _syncChangesSub;
  StreamSubscription<String>? _notificationTapSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncChangesSub?.cancel();
    _notificationTapSub?.cancel();
    _deepLinkSub?.cancel();
    _deepLinkHandler.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await ref.read(authProvider.notifier).loadIdentity();

    // The sync manager signs snapshots/invites as us and decides whether to
    // act as an admin, so it needs our identity and key pair.
    await _pushIdentityToSync();
    ref.listenManual(authProvider, (_, _) => _pushIdentityToSync());

    if (AppPlatform.canNotify) {
      _syncChangesSub = ref.read(syncManagerProvider).changes.listen((change) {
        final title = change.title;
        if (title == null) return;
        ref.read(notificationSchedulerProvider).notifyActivity(
              key: 'activity:${change.type.name}:${DateTime.now().millisecondsSinceEpoch}',
              title: title,
              body: change.body ?? '',
              groupId: change.groupId,
              payload: NotificationTarget(type: change.type, groupId: change.groupId, recordId: change.recordId).encode(),
            );
      });
      final onTap = widget.onNotificationTap;
      if (onTap != null) {
        _notificationTapSub = NotificationService.taps.listen((payload) {
          final target = NotificationTarget.decode(payload);
          if (target != null) onTap(target);
        });
      }
    }

    final onDeepLink = widget.onDeepLink;
    if (onDeepLink != null) {
      // Subscribe first: app_links emits the cold-start link as soon as a
      // listener attaches.
      _deepLinkSub = _deepLinkHandler.onDeepLink.listen(onDeepLink);
      _deepLinkHandler.init();
    }

    // Not awaited: node start can take a while and must never block the UI.
    _startNode();
  }

  Future<void> _pushIdentityToSync() async {
    final auth = ref.read(authProvider.notifier);
    final identity = ref.read(authProvider).identity;
    SimpleKeyPair? keyPair;
    if (identity != null && identity.canSign) {
      try {
        keyPair = await auth.requireSigningKeyPair();
      } catch (_) {}
    }
    ref.read(syncManagerProvider).setIdentity(peerId: identity?.peerId, keyPair: keyPair);
  }

  DateTime? _lastCloudBackupCheck;

  void _startNode() {
    unawaited(ref.read(syncManagerProvider).startBackground());
    _maybeCloudBackup();
  }

  /// WhatsApp-style opportunistic backup: whenever the app comes to the
  /// foreground, back up if enabled and the interval has passed (checked at
  /// most once an hour; the service applies the Wi-Fi rule).
  void _maybeCloudBackup() {
    if (!AppPlatform.isMobile) return;
    final now = DateTime.now();
    final last = _lastCloudBackupCheck;
    if (last != null && now.difference(last) < const Duration(hours: 1)) return;
    _lastCloudBackupCheck = now;
    unawaited(CloudBackupService().runIfDue());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final sync = ref.read(syncManagerProvider);
    switch (state) {
      case AppLifecycleState.resumed:
        _startNode(); // idempotent: re-arms the timer and syncs once
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // Desktop windows are long-lived and usually just lose focus; keeping
        // the node up there is the better trade. Phones stop it to save battery.
        if (AppPlatform.isMobile) sync.pauseBackground();
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
