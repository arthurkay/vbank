import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers/sync.dart';

/// Runs a sync round when the app opens and every time it returns to
/// the foreground, so members see each other's records without tapping
/// Sync now. Rounds are best-effort: failures stay in the sync log and
/// the next trigger retries. Overlapping triggers join the running
/// round instead of stacking up.
final class SyncOnResume extends ConsumerStatefulWidget {
  /// The screen below.
  final Widget child;

  /// Creates the trigger.
  const SyncOnResume({required this.child, super.key});

  @override
  ConsumerState<SyncOnResume> createState() => _SyncOnResumeState();
}

final class _SyncOnResumeState extends ConsumerState<SyncOnResume>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _sync();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _sync();
    }
  }

  /// One best-effort round now.
  void _sync() {
    final coordinator = ref.read(syncCoordinatorProvider);
    if (coordinator == null) {
      return;
    }
    unawaited(coordinator.synchronizeNow().then((_) {}, onError: (_) {}));
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
