import 'dart:typed_data';

enum BackupType { full, selective }

class AppBackup {
  final String id;
  final Uint8List encryptedPayload;
  final List<String> groupIds;
  final DateTime createdAt;
  final int version;
  final BackupType type;

  const AppBackup({
    required this.id,
    required this.encryptedPayload,
    required this.groupIds,
    required this.createdAt,
    this.version = 1,
    required this.type,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'encryptedPayload': encryptedPayload,
    'groupIds': groupIds,
    'createdAt': createdAt.toIso8601String(),
    'version': version,
    'type': type.name,
  };

  factory AppBackup.fromJson(Map<String, dynamic> json) => AppBackup(
    id: json['id'] as String,
    encryptedPayload: Uint8List.fromList((json['encryptedPayload'] as List).cast<int>()),
    groupIds: (json['groupIds'] as List).cast<String>(),
    createdAt: DateTime.parse(json['createdAt'] as String),
    version: json['version'] as int? ?? 1,
    type: BackupType.values.firstWhere(
      (t) => t.name == json['type'],
      orElse: () => BackupType.full,
    ),
  );
}

class IdentityBackup {
  final Uint8List encryptedPrivateKey;
  final String peerId;
  final DateTime backedUpAt;
  final String backupVersion;

  const IdentityBackup({
    required this.encryptedPrivateKey,
    required this.peerId,
    required this.backedUpAt,
    this.backupVersion = '1.0',
  });

  Map<String, dynamic> toJson() => {
    'encryptedPrivateKey': encryptedPrivateKey,
    'peerId': peerId,
    'backedUpAt': backedUpAt.toIso8601String(),
    'backupVersion': backupVersion,
  };

  factory IdentityBackup.fromJson(Map<String, dynamic> json) => IdentityBackup(
    encryptedPrivateKey: Uint8List.fromList((json['encryptedPrivateKey'] as List).cast<int>()),
    peerId: json['peerId'] as String,
    backedUpAt: DateTime.parse(json['backedUpAt'] as String),
    backupVersion: json['backupVersion'] as String? ?? '1.0',
  );
}
