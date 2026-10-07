import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../domain/group.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// The macOS home: the same auth gate and group list in Macos dress.
///
/// [onCreateIdentity] runs onboarding; tests pass a fake.
final class MacosHomePage extends ConsumerWidget {
  /// Called when the signed-out user taps Get started.
  final Future<void> Function()? onCreateIdentity;

  /// Creates the page.
  const MacosHomePage({super.key, this.onCreateIdentity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authProvider);
    if (auth.isLoading) {
      return const MacosWindow(
        child: MacosScaffold(
          children: [
            ContentArea(
              builder: _loading,
            ),
          ],
        ),
      );
    }
    if (!auth.isSignedIn) {
      return MacosWindow(
        child: MacosScaffold(
          children: [
            ContentArea(
              builder: (BuildContext context, ScrollController _) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'vBank',
                      style: MacosTheme.of(context).typography.largeTitle,
                    ),
                    const SizedBox(height: 8),
                    const Text('Village banking that works offline.'),
                    const SizedBox(height: 20),
                    PushButton(
                      controlSize: ControlSize.large,
                      onPressed: onCreateIdentity == null
                          ? null
                          : () => onCreateIdentity!(),
                      child: const Text('Get started'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }
    return const MacosGroupsPage();
  }

  static Widget _loading(BuildContext context, ScrollController _) =>
      const Center(child: ProgressCircle());
}

/// The group list: loading, empty and roster rows.
final class MacosGroupsPage extends ConsumerWidget {
  /// Creates the page.
  const MacosGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Group>> groups = ref.watch(groupListProvider);
    return MacosScaffold(
      toolBar: const ToolBar(title: Text('Groups')),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              groups.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (Object error, _) => Center(child: Text('Error: $error')),
            data: (List<Group> list) {
              if (list.isEmpty) {
                return const Center(
                  child: Text('No groups yet'),
                );
              }
              return ListView.builder(
                controller: controller,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                itemCount: list.length,
                itemBuilder: (BuildContext context, int i) {
                  final Group group = list[i];
                  return MacosListTile(
                    leading: const MacosIcon(CupertinoIcons.person_2_fill),
                    title: Text(
                      group.name,
                      style: MacosTheme.of(context).typography.headline,
                    ),
                    subtitle: Text('${group.memberCount} members'),
                    onClick: () => ref
                        .read(selectedGroupIdProvider.notifier)
                        .state = group.id,
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
