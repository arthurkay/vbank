import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/group.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// The Windows home: the same auth gate and group list in Fluent dress.
///
/// [onCreateIdentity] runs onboarding; tests pass a fake.
final class WindowsHomePage extends ConsumerWidget {
  /// Called when the signed-out user taps Get started.
  final Future<void> Function()? onCreateIdentity;

  /// Creates the page.
  const WindowsHomePage({super.key, this.onCreateIdentity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authProvider);
    if (auth.isLoading) {
      return const NavigationView(content: Center(child: ProgressRing()));
    }
    if (!auth.isSignedIn) {
      return NavigationView(
        content: ScaffoldPage(
          content: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'vBank',
                  style: FluentTheme.of(context).typography.titleLarge,
                ),
                const SizedBox(height: 8),
                const Text('Village banking that works offline.'),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: onCreateIdentity == null
                      ? null
                      : () => onCreateIdentity!(),
                  child: const Text('Get started'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    return const WindowsGroupsPage();
  }
}

/// The group list: loading, empty and roster rows.
final class WindowsGroupsPage extends ConsumerWidget {
  /// Creates the page.
  const WindowsGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Group>> groups = ref.watch(groupListProvider);
    return ScaffoldPage(
      header: const PageHeader(title: Text('Groups')),
      content: groups.when(
        loading: () => const Center(child: ProgressRing()),
        error: (Object error, _) => Center(child: Text('Error: $error')),
        data: (List<Group> list) {
          if (list.isEmpty) {
            return const Center(
              child: Text('No groups yet'),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
            itemCount: list.length,
            itemBuilder: (BuildContext context, int i) {
              final Group group = list[i];
              return Card(
                padding: EdgeInsets.zero,
                margin: const EdgeInsets.only(bottom: 6),
                child: ListTile(
                  leading: const Icon(FluentIcons.group, size: 18),
                  title: Text(group.name),
                  subtitle: Text('${group.memberCount} members'),
                  trailing: const Icon(FluentIcons.chevron_right, size: 12),
                  onPressed: () => ref
                      .read(selectedGroupIdProvider.notifier)
                      .state = group.id,
                ),
              );
            },
          );
        },
      ),
    );
  }
}
