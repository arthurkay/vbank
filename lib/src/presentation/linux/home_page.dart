import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../domain/core/result.dart';
import '../../domain/group.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import 'create_group_page.dart';
import 'group_detail_page.dart';
import 'join_group_page.dart';

/// The Linux home: the same auth gate and group list in Yaru dress.
///
/// [onCreateIdentity] runs onboarding; tests pass a fake.
final class LinuxHomePage extends ConsumerWidget {
  /// Called when the signed-out user taps Get started.
  final Future<void> Function()? onCreateIdentity;

  /// Joins a group from a link; null hides the join entries (tests).
  final Future<Result<Unit>> Function({
    required String link,
    required String displayName,
  })?
  onJoinGroup;

  /// Creates the page.
  const LinuxHomePage({super.key, this.onCreateIdentity, this.onJoinGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authProvider);
    if (auth.isLoading) {
      return const Scaffold(
        body: Center(child: YaruCircularProgressIndicator()),
      );
    }
    if (!auth.isSignedIn) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'vBank',
                style: Theme.of(context).textTheme.headlineMedium,
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
      );
    }
    final String? selected = ref.watch(selectedGroupIdProvider);
    if (selected != null) {
      return LinuxGroupDetailPage(groupId: selected);
    }
    final onJoinGroup = this.onJoinGroup;
    return YaruDetailPage(
      appBar: AppBar(
        title: const Text('Groups'),
        actions: [
          IconButton(
            key: const ValueKey('create-group-button'),
            tooltip: 'New group',
            icon: const Icon(YaruIcons.plus),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const LinuxCreateGroupPage(),
              ),
            ),
          ),
          if (onJoinGroup != null)
            IconButton(
              key: const ValueKey('join-group-button'),
              tooltip: 'Join group',
              icon: const Icon(YaruIcons.insert_link),
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) =>
                      LinuxJoinGroupPage(onJoin: onJoinGroup),
                ),
              ),
            ),
        ],
      ),
      body: _GroupList(joinGroup: onJoinGroup),
    );
  }
}

/// The group list: loading, empty and roster rows.
final class _GroupList extends ConsumerWidget {
  /// Join callback for the empty state; null hides the join button.
  final Future<Result<Unit>> Function({
    required String link,
    required String displayName,
  })?
  joinGroup;

  /// Creates the list.
  const _GroupList({this.joinGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Group>> groups = ref.watch(groupListProvider);
    return groups.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (Object error, _) => Center(child: Text('Error: $error')),
      data: (List<Group> list) {
        if (list.isEmpty) {
          final joinGroup = this.joinGroup;
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No groups yet'),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const LinuxCreateGroupPage(),
                    ),
                  ),
                  child: const Text('New group'),
                ),
                if (joinGroup != null) ...[
                  const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            LinuxJoinGroupPage(onJoin: joinGroup),
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
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          itemCount: list.length,
          itemBuilder: (BuildContext context, int i) {
            final Group group = list[i];
            return YaruListTile(
              leading: CircleAvatar(
                child: Text(
                  group.name.isEmpty ? '?' : group.name[0].toUpperCase(),
                ),
              ),
              title: Text(group.name),
              subtitle: Text('${group.memberCount} members'),
              trailing: const Icon(YaruIcons.pan_end),
              onTap: () => ref
                  .read(selectedGroupIdProvider.notifier)
                  .state = group.id,
            );
          },
        );
      },
    );
  }
}
