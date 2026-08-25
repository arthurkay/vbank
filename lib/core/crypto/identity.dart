import 'dart:typed_data';
import 'package:cryptography/cryptography.dart';
import 'package:uuid/uuid.dart';
import 'signing.dart';

class UserIdentity {
  final String peerId;
  final String displayName;
  final Uint8List publicKey;
  final DateTime createdAt;

  const UserIdentity({
    required this.peerId,
    required this.displayName,
    required this.publicKey,
    required this.createdAt,
  });

  Map<String, dynamic> toMap() => {
    'peer_id': peerId,
    'display_name': displayName,
    'public_key': publicKey,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory UserIdentity.fromMap(Map<String, dynamic> map) => UserIdentity(
    peerId: map['peer_id'] as String,
    displayName: map['display_name'] as String,
    publicKey: Uint8List.fromList(map['public_key'] as List<int>),
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );
}

/// A freshly generated identity together with the key material that must be
/// persisted so the user can keep signing as this identity.
class GeneratedIdentity {
  final UserIdentity identity;
  final SimpleKeyPair keyPair;

  /// 32-byte Ed25519 seed. Store this (encrypted at rest); it is sufficient to
  /// rebuild [keyPair] via [SigningService.keyPairFromSeed].
  final Uint8List privateKeySeed;

  const GeneratedIdentity({
    required this.identity,
    required this.keyPair,
    required this.privateKeySeed,
  });
}

class IdentityManager {
  /// Fixed UUID namespace so that the same public key always maps to the same
  /// peer ID on every device (uuid v5 is deterministic given namespace+name).
  static const _peerIdNamespace = '3f2d1c4b-7e8a-4b9c-9d1e-2a5f6b7c8d9e';
  static const _uuid = Uuid();

  static String generatePeerId(List<int> publicKey) {
    final hex = publicKey
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
    return 'vbank_${_uuid.v5(_peerIdNamespace, hex)}';
  }

  static Future<GeneratedIdentity> createIdentity(String displayName) async {
    final keyPair = await SigningService.generateKeyPair();
    final publicKeyBytes = await SigningService.extractPublicKeyBytes(keyPair);
    final seed = await SigningService.extractSeed(keyPair);
    final peerId = generatePeerId(publicKeyBytes);

    return GeneratedIdentity(
      identity: UserIdentity(
        peerId: peerId,
        displayName: displayName,
        publicKey: Uint8List.fromList(publicKeyBytes),
        createdAt: DateTime.now().toUtc(),
      ),
      keyPair: keyPair,
      privateKeySeed: Uint8List.fromList(seed),
    );
  }
}
