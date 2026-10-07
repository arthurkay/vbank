import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/sync_coordinator.dart';

/// The sync coordinator, installed by the platform startup. Null in
/// widget tests, which never start a node: screens treat null as
/// "sync unavailable" and skip their post-write round.
final syncCoordinatorProvider = Provider<SyncCoordinator?>((ref) => null);
