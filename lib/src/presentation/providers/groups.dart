import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/group.dart';
import '../app_scope.dart';

/// The open group's id, or null on the list.
final selectedGroupIdProvider = StateProvider<String?>((ref) => null);

/// All groups with members, live, by name.
final groupListProvider = StreamProvider<List<Group>>((ref) {
  final groups = ref.watch(appRepositoriesProvider).groups;
  return groups.watchGroups();
});

/// The open group with members, live. Null while nothing is selected.
final selectedGroupProvider = StreamProvider<Group?>((ref) async* {
  final id = ref.watch(selectedGroupIdProvider);
  if (id == null) {
    yield null;
    return;
  }
  final groups = ref.watch(appRepositoriesProvider).groups;
  await for (final List<Group> all in groups.watchGroups()) {
    Group? open;
    for (final Group g in all) {
      if (g.id == id) {
        open = g;
      }
    }
    yield open;
  }
});
