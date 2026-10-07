import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/core/result.dart';
import '../../domain/group.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import 'create_group_page.dart';
import 'group_detail_page.dart';
import 'join_group_page.dart';

/// The Windows home: the same auth gate and group list in Fluent dress.
///
/// [onCreateIdentity] runs onboarding; tests pass a fake.
final class WindowsHomePage extends ConsumerWidget {
  /// Called when the signed-out user taps Get started.
  final Future<void> Function()? onCreateIdentity;

  /// Joins a group from a link; null hides the join entries (tests).
  final Future<Result<Unit>> Function({
    required String link,
    required String displayName,
  })?
  onJoinGroup;

  /// Creates the page.
  const WindowsHomePage({super.key, this.onCreateIdentity, this.onJoinGroup});

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
    final String? selected = ref.watch(selectedGroupIdProvider);
    if (selected != null) {
      return WindowsGroupDetailPage(groupId: selected);
    }
    return WindowsGroupsPage(joinGroup: onJoinGroup);
  }
}

/// The group list: loading, empty and roster rows.
final class WindowsGroupsPage extends ConsumerWidget {
  /// Join callback for entries; null hides them.
  final Future<Result<Unit>> Function({
    required String link,
    required String displayName,
  })?
  joinGroup;

  /// Creates the page.
  const WindowsGroupsPage({super.key, this.joinGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Group>> groups = ref.watch(groupListProvider);
    final joinGroup = this.joinGroup;
    return ScaffoldPage(
      header: PageHeader(
        title: const Text('Groups'),
        commandBar: CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              key: const ValueKey('create-group-button'),
              icon: const Icon(FluentIcons.add),
              label: const Text('New group'),
              onPressed: () => Navigator.push(
                context,
                FluentPageRoute<void>(
                  builder: (_) => const WindowsCreateGroupPage(),
                ),
              ),
            ),
            if (joinGroup != null)
              CommandBarButton(
                key: const ValueKey('join-group-button'),
                icon: const Icon(FluentIcons.link),
                label: const Text('Join group'),
                onPressed: () => Navigator.push(
                  context,
                  FluentPageRoute<void>(
                    builder: (_) =>
                        WindowsJoinGroupPage(onJoin: joinGroup),
                  ),
                ),
              ),
          ],
        ),
      ),
      content: groups.when(
        loading: () => const Center(child: ProgressRing()),
        error: (Object error, _) => Center(child: Text('Error: $error')),
        data: (List<Group> list) {
          if (list.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('No groups yet'),
                  const SizedBox(height: 12),
                  FilledButton(
                    onPressed: () => Navigator.push(
                      context,
                      FluentPageRoute<void>(
                        builder: (_) => const WindowsCreateGroupPage(),
                      ),
                    ),
                    child: const Text('New group'),
                  ),
                  if (joinGroup != null) ...[
                    const SizedBox(height: 12),
                    Button(
                      onPressed: () => Navigator.push(
                        context,
                        FluentPageRoute<void>(
                          builder: (_) =>
                              WindowsJoinGroupPage(onJoin: joinGroup),
                        ),
                      ),
                      child: const Text('Join group'),
                    ),
                  ],
                ],
              ),
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
