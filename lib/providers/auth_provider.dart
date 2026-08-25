import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/crypto/identity.dart';
import '../core/crypto/signing.dart';
import '../core/storage/user_identity_dao.dart';

class AuthState {
  final bool isLoaded;
  final bool isLoggedIn;
  final UserIdentityData? identity;

  const AuthState({
    this.isLoaded = false,
    this.isLoggedIn = false,
    this.identity,
  });

  AuthState copyWith({
    bool? isLoaded,
    bool? isLoggedIn,
    UserIdentityData? identity,
  }) {
    return AuthState(
      isLoaded: isLoaded ?? this.isLoaded,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      identity: identity ?? this.identity,
    );
  }
}

class NotSignedInException implements Exception {
  final String message;
  const NotSignedInException([this.message = 'No local identity']);
  @override
  String toString() => message;
}

class AuthNotifier extends StateNotifier<AuthState> {
  final UserIdentityDao _dao = UserIdentityDao();

  /// Cached key pair rebuilt from the stored seed; cleared on logout.
  SimpleKeyPair? _keyPair;

  AuthNotifier() : super(const AuthState());

  Future<void> loadIdentity() async {
    final identity = await _dao.get();
    _keyPair = null;
    state = AuthState(
      isLoaded: true,
      isLoggedIn: identity != null,
      identity: identity,
    );
  }

  Future<UserIdentityData> createIdentity(String displayName) async {
    final generated = await IdentityManager.createIdentity(displayName);

    final data = UserIdentityData(
      peerId: generated.identity.peerId,
      displayName: generated.identity.displayName,
      publicKey: generated.identity.publicKey,
      privateKey: generated.privateKeySeed,
      createdAt: generated.identity.createdAt,
    );

    await _dao.insert(data);
    _keyPair = generated.keyPair;

    state = state.copyWith(
      isLoaded: true,
      isLoggedIn: true,
      identity: data,
    );

    return data;
  }

  Future<void> restoreIdentity(UserIdentityData identity) async {
    await _dao.insert(identity);
    _keyPair = null;
    state = state.copyWith(
      isLoaded: true,
      isLoggedIn: true,
      identity: identity,
    );
  }

  /// The current identity, or throws if none is loaded.
  UserIdentityData requireIdentity() {
    final identity = state.identity;
    if (identity == null) throw const NotSignedInException();
    return identity;
  }

  /// The user's long-lived Ed25519 key pair for signing transactions, loans,
  /// invites, etc. Everything a member signs must use this key so peers can
  /// verify it against the member's stored public key.
  Future<SimpleKeyPair> requireSigningKeyPair() async {
    final cached = _keyPair;
    if (cached != null) return cached;

    final identity = requireIdentity();
    final seed = identity.privateKey;
    if (seed == null || seed.isEmpty) {
      throw const NotSignedInException(
        'This identity has no private key stored. Restore from a backup or '
        'create a new account.',
      );
    }
    final keyPair = await SigningService.keyPairFromSeed(seed);
    _keyPair = keyPair;
    return keyPair;
  }

  Uint8List requirePublicKey() => requireIdentity().publicKey;

  Future<void> logout() async {
    await _dao.delete();
    _keyPair = null;
    state = const AuthState(isLoaded: true);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  return AuthNotifier();
});

final currentUserProvider = Provider<UserIdentityData?>((ref) {
  return ref.watch(authProvider).identity;
});
