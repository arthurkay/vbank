import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_ui/macos_ui.dart';

import '../../domain/core/result.dart';
import '../../domain/group.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';
import 'create_group_page.dart';
import 'group_detail_page.dart';
import 'identity_page.dart';
import 'join_group_page.dart';

/// The macOS home: the same auth gate and group list in Macos dress.
///
/// [onCreateIdentity] runs onboarding; tests pass a fake.
final class MacosHomePage extends ConsumerWidget {
  /// Called when the signed-out user taps Get started.
  final Future<void> Function()? onCreateIdentity;

  /// Joins a group from a link; null hides the join entries (tests).
  final Future<Result<Unit>> Function({
    required String link,
    required String displayName,
  })?
  onJoinGroup;

  /// Creates the page.
  const MacosHomePage({super.key, this.onCreateIdentity, this.onJoinGroup});

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
    final String? selected = ref.watch(selectedGroupIdProvider);
    if (selected != null) {
      return MacosGroupDetailPage(groupId: selected);
    }
    return MacosGroupsPage(joinGroup: onJoinGroup);
  }

  static Widget _loading(BuildContext context, ScrollController _) =>
      const Center(child: ProgressCircle());
}

/// The group list: loading, empty and roster rows.
final class MacosGroupsPage extends ConsumerWidget {
  /// Join callback for entries; null hides them.
  final Future<Result<Unit>> Function({
    required String link,
    required String displayName,
  })?
  joinGroup;

  /// Creates the page.
  const MacosGroupsPage({super.key, this.joinGroup});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AsyncValue<List<Group>> groups = ref.watch(groupListProvider);
    final joinGroup = this.joinGroup;
    return MacosScaffold(
      toolBar: ToolBar(
        title: const Text('Groups'),
        actions: [
          ToolBarIconButton(
            key: const ValueKey('create-group-button'),
            label: 'New group',
            icon: const MacosIcon(CupertinoIcons.add),
            showLabel: false,
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => const MacosCreateGroupPage(),
              ),
            ),
          ),
          if (joinGroup != null)
            ToolBarIconButton(
              key: const ValueKey('join-group-button'),
              label: 'Join group',
              icon: const MacosIcon(CupertinoIcons.link),
              showLabel: false,
              onPressed: () => Navigator.push(
                context,
                CupertinoPageRoute<void>(
                  builder: (_) =>
                      MacosJoinGroupPage(onJoin: joinGroup),
                ),
              ),
            ),
          ToolBarIconButton(
            key: const ValueKey('identity-button'),
            label: 'Identity',
            icon: const MacosIcon(CupertinoIcons.person_crop_circle),
            showLabel: false,
            onPressed: () => Navigator.push(
              context,
              CupertinoPageRoute<void>(
                builder: (_) => const MacosIdentityPage(),
              ),
            ),
          ),
        ],
      ),
      children: [
        ContentArea(
          builder: (BuildContext context, ScrollController controller) =>
              groups.when(
            loading: () => const Center(child: ProgressCircle()),
            error: (Object error, _) => Center(child: Text('Error: $error')),
            data: (List<Group> list) {
              if (list.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('No groups yet'),
                      const SizedBox(height: 12),
                      PushButton(
                        controlSize: ControlSize.large,
                        onPressed: () => Navigator.push(
                          context,
                          CupertinoPageRoute<void>(
                            builder: (_) => const MacosCreateGroupPage(),
                          ),
                        ),
                        child: const Text('New group'),
                      ),
                      if (joinGroup != null) ...[
                        const SizedBox(height: 12),
                        PushButton(
                          controlSize: ControlSize.large,
                          secondary: true,
                          onPressed: () => Navigator.push(
                            context,
                            CupertinoPageRoute<void>(
                              builder: (_) =>
                                  MacosJoinGroupPage(onJoin: joinGroup),
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
