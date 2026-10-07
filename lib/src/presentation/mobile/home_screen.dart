import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart';

import '../../domain/group.dart';
import '../providers/auth.dart';
import '../providers/groups.dart';

/// The mobile home: an auth gate over the group list.
///
/// [onCreateIdentity] runs the onboarding flow (keypair generation plus
/// secure storage live in platform code); widget tests pass a fake that
/// writes the identity row directly.
final class MobileHomeScreen extends ConsumerWidget {
  /// Called when the signed-out user taps Get started.
  final Future<void> Function()? onCreateIdentity;

  /// Called with the captured render for golden-style assertions.
  const MobileHomeScreen({super.key, this.onCreateIdentity});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final AuthState auth = ref.watch(authProvider);
    if (auth.isLoading) {
      return const Scaffold(
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!auth.isSignedIn) {
      return Scaffold(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('vBank').xLarge.bold,
              const Gap(8),
              const Text('Village banking that works offline.'),
              const Gap(20),
              PrimaryButton(
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
    return const Scaffold(
      headers: [AppBar(title: Text('Groups'))],
      child: _GroupList(),
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
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, _) => Center(child: Text('Error: $error')),
      data: (List<Group> list) {
        if (list.isEmpty) {
          return const Center(
            child: Text('No groups yet'),
          );
        }
        return ListView.builder(
          itemCount: list.length,
          itemBuilder: (BuildContext context, int i) {
            final Group group = list[i];
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => ref.read(selectedGroupIdProvider.notifier).state =
                  group.id,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(group.name).medium,
                          Text(
                            '${group.memberCount} members',
                          ).small.muted,
                        ],
                      ),
                    ),
                    const Icon(LucideIcons.chevronRight, size: 16),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
