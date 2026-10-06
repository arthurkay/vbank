import '../../domain/backup.dart';
import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/identity.dart';
import 'dto.dart';

/// Row mapping for `backups` and `identity`.
abstract final class BackupDto {
  /// Serializes [backup] to a `backups` row.
  ///
  /// Group ids ride as one comma-joined string; ids are UUIDs and never
  /// contain commas.
  static Map<String, Object?> toRow(AppBackup backup) => {
        'id': backup.id,
        'encrypted_payload': backup.encryptedPayload,
        'group_ids': backup.groupIds.join(','),
        'created_at': Dto.instantValue(backup.createdAt),
        'version': backup.version,
        'backup_type': backup.type.name,
      };

  /// Parses a `backups` row.
  static Result<AppBackup> fromRow(Map<String, Object?> row) {
    try {
      final String joined = Dto.text(row, 'group_ids');
      return Ok(
        AppBackup(
          id: Dto.text(row, 'id'),
          encryptedPayload: Dto.bytes(row, 'encrypted_payload'),
          groupIds: joined.isEmpty ? const [] : joined.split(','),
          createdAt: Dto.instant(row, 'created_at'),
          version: Dto.integer(row, 'version'),
          type: Dto.enumeration(row, 'backup_type', BackupType.values),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}

/// Row mapping for `identity` (at most one row: this device's identity).
abstract final class IdentityDto {
  /// Serializes [identity] to the `identity` row.
  static Map<String, Object?> toRow(UserIdentity identity) => {
        'peer_id': identity.peerId,
        'display_name': identity.displayName,
        'public_key': identity.publicKey,
        'created_at': Dto.instantValue(identity.createdAt),
      };

  /// Parses the `identity` row.
  static Result<UserIdentity> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        UserIdentity(
          peerId: Dto.text(row, 'peer_id'),
          displayName: Dto.text(row, 'display_name'),
          publicKey: Dto.bytes(row, 'public_key'),
          createdAt: Dto.instant(row, 'created_at'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
