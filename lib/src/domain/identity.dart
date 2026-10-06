import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';

/// Who this device is to every group: a peer id plus a human name.
///
/// The private key never appears here — it lives in the platform keystore
/// (Android Keystore / iOS Keychain) and only signing touches it.
final class UserIdentity {
  /// Ed25519 public key, also the IPFS peer id.
  final String peerId;

  /// The name groups know this person by.
  final String displayName;

  /// Ed25519 public key bytes.
  final Uint8List publicKey;

  /// When the identity was created.
  final DateTime createdAt;

  /// Creates an identity.
  const UserIdentity({
    required this.peerId,
    required this.displayName,
    required this.publicKey,
    required this.createdAt,
  });

  /// Structural checks: identifiers present.
  Result<Unit> validate() {
    if (peerId.isEmpty) {
      return const Err(ValidationFailure('identityPeerIdEmpty'));
    }
    if (displayName.trim().isEmpty) {
      return const Err(ValidationFailure('identityNameEmpty'));
    }
    return const Ok(unit);
  }

  /// Copies this identity, replacing the display name.
  UserIdentity copyWith({String? displayName}) => UserIdentity(
        peerId: peerId,
        displayName: displayName ?? this.displayName,
        publicKey: publicKey,
        createdAt: createdAt,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserIdentity &&
          peerId == other.peerId &&
          displayName == other.displayName &&
          bytesEqual(publicKey, other.publicKey) &&
          createdAt == other.createdAt;

  @override
  int get hashCode => Object.hash(
        peerId,
        displayName,
        bytesHash(publicKey),
        createdAt,
      );
}

/// A PIN-encrypted private key for moving to a new device: scan, enter the
/// PIN, and the keypair is restored.
final class IdentityBackup {
  /// The private key, encrypted with the user's PIN (XChaCha20-Poly1305).
  final Uint8List encryptedPrivateKey;

  /// Whose key this is.
  final String peerId;

  /// When the backup was taken.
  final DateTime backedUpAt;

  /// Format version, for future migrations.
  final String backupVersion;

  /// Creates an identity backup.
  const IdentityBackup({
    required this.encryptedPrivateKey,
    required this.peerId,
    required this.backedUpAt,
    this.backupVersion = '1.0',
  });

  /// Structural checks: identifiers present.
  Result<Unit> validate() {
    if (peerId.isEmpty) {
      return const Err(ValidationFailure('identityBackupPeerIdEmpty'));
    }
    if (encryptedPrivateKey.isEmpty) {
      return const Err(ValidationFailure('identityBackupPayloadEmpty'));
    }
    return const Ok(unit);
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IdentityBackup &&
          bytesEqual(encryptedPrivateKey, other.encryptedPrivateKey) &&
          peerId == other.peerId &&
          backedUpAt == other.backedUpAt &&
          backupVersion == other.backupVersion;

  @override
  int get hashCode => Object.hash(
        bytesHash(encryptedPrivateKey),
        peerId,
        backedUpAt,
        backupVersion,
      );
}
