import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../app/sync_coordinator.dart';
import '../providers/sync.dart';

/// Sync state, relays and log in Macos dress.
final class MacosSyncStatusPage extends ConsumerStatefulWidget {
  /// Creates the page.
  const MacosSyncStatusPage({super.key});

  @override
  ConsumerState<MacosSyncStatusPage> createState() =>
      _MacosSyncStatusPageState();
}

final class _MacosSyncStatusPageState
    extends ConsumerState<MacosSyncStatusPage> {
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
    return MacosWindow(
      child: MacosScaffold(
        toolBar: ToolBar(
          leading: MacosBackButton(
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Sync'),
        ),
        children: [
          ContentArea(
            builder: (BuildContext context, ScrollController controller) =>
                ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
              children: [
                Row(
                  children: [
                    Text(
                      state.when(
                        loading: () => '…',
                        error: (_, _) => 'error',
                        data: (SyncState s) => s.name,
                      ),
                    ),
                    const SizedBox(width: 8),
                    PushButton(
                      controlSize: ControlSize.large,
                      onPressed: _busy ? null : _syncNow,
                      child: Text(_busy ? 'Syncing…' : 'Sync now'),
                    ),
                  ],
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(_error!),
                ],
                const SizedBox(height: 20),
                const Text('Relays'),
                const SizedBox(height: 8),
                ...relays.when(
                  loading: () => const [
                    Center(child: ProgressCircle()),
                  ],
                  error: (Object error, _) => [Text('Error: $error')],
                  data: (List<String> addrs) => [
                    if (addrs.isEmpty) const Text('None configured.'),
                    for (final String addr in addrs)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Text(addr),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: MacosTextField(
                        controller: _relay,
                        placeholder: '/dns4/…/tcp/4001/p2p/…',
                      ),
                    ),
                    const SizedBox(width: 8),
                    PushButton(
                      controlSize: ControlSize.large,
                      secondary: true,
                      onPressed: _addRelay,
                      child: const Text('Add'),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Text('Log'),
                const SizedBox(height: 8),
                if (log.isEmpty) const Text('No sync activity yet.'),
                for (final SyncEvent event in log.take(30))
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Text(event.message),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
