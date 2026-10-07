import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/identity.dart';
import '../app_scope.dart';

/// Signed-in state: loading while the identity row reads, then either an
/// identity or nothing (fresh install → onboarding).
final class AuthState {
  /// True while reading.
  final bool isLoading;

  /// This device's identity, or null when never created.
  final UserIdentity? identity;

  /// Creates the state.
  const AuthState({required this.isLoading, required this.identity});

  /// Still reading.
  static const AuthState loading = AuthState(
    isLoading: true,
    identity: null,
  );

  /// True once an identity exists.
  bool get isSignedIn => !isLoading && identity != null;
}

/// Watches the device identity row.
final class AuthNotifier extends StateNotifier<AuthState> {
  /// Repository source for identity reads.
  final Ref _ref;

  /// Creates the notifier, loading immediately.
  AuthNotifier(this._ref) : super(AuthState.loading) {
    refresh();
  }

  /// Re-reads the identity row.
  Future<void> refresh() async {
    state = AuthState.loading;
    final result = await _ref
        .read(appRepositoriesProvider)
        .backups
        .loadIdentity();
    state = AuthState(
      isLoading: false,
      identity: result.isOk ? result.value : null,
    );
  }
}

/// The signed-in state, refreshing on startup.
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>(
  (ref) => AuthNotifier(ref),
);
