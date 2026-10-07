import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:yaru/yaru.dart';

import '../../domain/group.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// The Linux home: the same auth gate and group list in Yaru dress.
///
/// [onCreateIdentity] runs onboarding; tests pass a fake.
final class LinuxHomePage extends ConsumerWidget {
  /// Called when the signed-out user taps Get started.
  final Future<void> Function()? onCreateIdentity;

  /// Creates the page.
  const LinuxHomePage({super.key, this.onCreateIdentity});

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
    return YaruDetailPage(
      appBar: AppBar(title: const Text('Groups')),
      body: const _GroupList(),
    );
  }
}

/// The group list: loading, empty and roster rows.
final class _GroupList extends ConsumerWidget {
  /// Creates the list.
  const _GroupList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Group>> groups = ref.watch(groupListProvider);
    return groups.when(
      loading: () => const Center(child: YaruCircularProgressIndicator()),
      error: (Object error, _) => Center(child: Text('Error: $error')),
      data: (List<Group> list) {
        if (list.isEmpty) {
          return const Center(
            child: Text('No groups yet'),
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
