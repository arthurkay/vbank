import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/invites.dart';
import '../app_scope.dart';

/// A group's invites, newest first, live.
final inviteListProvider =
    StreamProvider.family<List<Invite>, String>((ref, groupId) {
  final invites = ref.watch(appRepositoriesProvider).invites;
  return invites.watchByGroup(groupId);
});
