import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';

/// How much of the device a backup holds.
enum BackupType {
  /// Everything: every group.
  full,

  /// Named groups only.
  selective,
}

/// An encrypted copy of local data for moving devices: restore, enter the
/// passphrase, carry on.
final class AppBackup {
  /// This backup's id.
  final String id;

  /// All local data, encrypted with the user's passphrase.
  final Uint8List encryptedPayload;

  /// Groups included (all of them when [type] is `full`).
  final List<String> groupIds;

  /// When it was taken.
  final DateTime createdAt;

  /// Format version, for future migrations.
  final int version;

  /// How much it holds.
  final BackupType type;

  /// Creates a backup record.
  const AppBackup({
    required this.id,
    required this.encryptedPayload,
    required this.groupIds,
    required this.createdAt,
    this.version = 1,
    required this.type,
  });

  /// Structural checks: identifiers present, payload non-empty, sane version.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('backupIdEmpty'));
    }
    if (encryptedPayload.isEmpty) {
      return const Err(ValidationFailure('backupPayloadEmpty'));
    }
    if (version < 1) {
      return const Err(ValidationFailure('backupVersionRange'));
    }
    return const Ok(unit);
  }

  static bool _idsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AppBackup &&
          id == other.id &&
          bytesEqual(encryptedPayload, other.encryptedPayload) &&
          _idsEqual(groupIds, other.groupIds) &&
          createdAt == other.createdAt &&
          version == other.version &&
          type == other.type;

  @override
  int get hashCode => Object.hash(
        id,
        bytesHash(encryptedPayload),
        Object.hashAll(groupIds),
        createdAt,
        version,
        type,
      );
}
