import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../app/sync_coordinator.dart';
import '../providers/sync.dart';

/// Sync state, relays and log in shadcn dress. The Sync now button
/// runs a round immediately instead of waiting for the periodic one.
final class MobileSyncStatusScreen extends ConsumerStatefulWidget {
  /// Creates the screen.
  const MobileSyncStatusScreen({super.key});

  @override
  ConsumerState<MobileSyncStatusScreen> createState() =>
      _MobileSyncStatusScreenState();
}

final class _MobileSyncStatusScreenState
    extends ConsumerState<MobileSyncStatusScreen> {
  final TextEditingController _relay = TextEditingController();
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _relay.dispose();
    super.dispose();
  }

  /// Runs a round now.
  Future<void> _syncNow() async {
    final SyncCoordinator? coordinator = ref.read(syncCoordinatorProvider);
    if (coordinator == null) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await coordinator.synchronizeNow();
    } catch (e) {
      if (mounted) {
        setState(() => _error = '$e');
      }
    }
    if (mounted) {
      setState(() => _busy = false);
    }
    ref.invalidate(relayListProvider);
  }

  /// Short peer id for a relay multiaddr (`…/p2p/<id>`).
  static String _shortPeer(String addr) {
    final String id = addr.split('/p2p/').last;
    return id.length <= 8 ? id : id.substring(0, 8);
  }

  /// Adds a user relay address.
  Future<void> _addRelay() async {
    final SyncCoordinator? coordinator = ref.read(syncCoordinatorProvider);
    final String addr = _relay.text.trim();
    if (coordinator == null || addr.isEmpty) {
      return;
    }
    await coordinator.addRelays([addr]);
    if (mounted) {
      setState(() => _relay.clear());
    }
    ref.invalidate(relayListProvider);
  }

  @override
  Widget build(BuildContext context) {
    final AsyncValue<SyncState> state = ref.watch(syncStateProvider);
    // Rebuilds on every log line so the log below stays fresh.
    ref.watch(syncEventProvider);
    final SyncCoordinator? coordinator = ref.watch(syncCoordinatorProvider);
    final AsyncValue<List<String>> relays = ref.watch(relayListProvider);
    final List<SyncEvent> log = List<SyncEvent>.from(
      coordinator?.recentLog ?? const [],
    ).reversed.toList();
    return Scaffold(
      headers: [
        AppBar(
          leading: [
            IconButton.ghost(
              icon: const Icon(LucideIcons.arrowLeft),
              onPressed: () => Navigator.pop(context),
            ),
          ],
          title: const Text('Sync'),
        ),
      ],
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Row(
            children: [
              Text(
                state.when(
                  loading: () => '…',
                  error: (_, _) => 'Attention needed',
                  data: (SyncState s) => switch (s) {
                    SyncState.syncing => 'Syncing…',
                    SyncState.error => 'Attention needed',
                    SyncState.idle => 'Up to date',
                  },
                ),
              ).small.semiBold.muted,
              const Gap(8),
              PrimaryButton(
                onPressed: _busy ? null : _syncNow,
                child: Text(_busy ? 'Syncing…' : 'Sync now'),
              ),
            ],
          ),
          const Gap(4),
          const Text(
            'Sync runs on its own when the app opens and returns. '
            'This button forces a round right now.',
          ).small.muted,
          if (_error != null) ...[const Gap(8), Text(_error!).small],
          const Gap(20),
          Text('Relays').small.semiBold.muted,
          const Gap(8),
          ...relays.when(
            loading: () => const [Center(child: CircularProgressIndicator())],
            error: (Object error, _) => [Text('Error: $error')],
            data: (List<String> addrs) => [
              if (addrs.isEmpty)
                const Text(
                  'None configured — members can only sync on the same Wi-Fi.',
                ).small.muted,
              for (final String addr in addrs)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text('Relay ${_shortPeer(addr)}').xSmall.muted,
                ),
            ],
          ),
          const Gap(8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _relay,
                  placeholder: const Text('/dns4/…/tcp/4001/p2p/…'),
                  onSubmitted: (_) => _addRelay(),
                ),
              ),
              const Gap(8),
              OutlineButton(onPressed: _addRelay, child: const Text('Add')),
            ],
          ),
          const Gap(20),
          Text('Log').small.semiBold.muted,
          const Gap(8),
          if (log.isEmpty) const Text('No sync activity yet.').small.muted,
          for (final SyncEvent event in log.take(30))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Text(event.message).xSmall.muted,
            ),
        ],
      ),
    );
  }
}
