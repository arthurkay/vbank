import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'database.dart';

class UserIdentityDao {
  Future<void> insert(UserIdentityData identity) async {
    final db = await AppDatabase.getInstance();
    // There is a single local identity; restoring over an existing row must
    // replace it rather than fail on the primary key.
    await db.insert(
      'user_identity',
      identity.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<UserIdentityData?> get() async {
    final db = await AppDatabase.getInstance();
    final result = await db.query('user_identity', limit: 1);
    if (result.isEmpty) return null;
    return UserIdentityData.fromMap(result.first);
  }

  Future<void> update(UserIdentityData identity) async {
    final db = await AppDatabase.getInstance();
    await db.update(
      'user_identity',
      identity.toMap(),
      where: 'peer_id = ?',
      whereArgs: [identity.peerId],
    );
  }

  Future<void> delete() async {
    final db = await AppDatabase.getInstance();
    await db.delete('user_identity');
  }
}

class UserIdentityData {
  final String peerId;
  final String displayName;
  final Uint8List publicKey;

  /// 32-byte Ed25519 seed. Null only for identities created before the key
  /// was persisted (schema v1) — such identities cannot sign.
  final Uint8List? privateKey;
  final DateTime createdAt;

  const UserIdentityData({
    required this.peerId,
    required this.displayName,
    required this.publicKey,
    this.privateKey,
    required this.createdAt,
  });

  bool get canSign => privateKey != null && privateKey!.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'peer_id': peerId,
    'display_name': displayName,
    'public_key': publicKey,
    'private_key': privateKey,
    'created_at': createdAt.millisecondsSinceEpoch,
  };

  factory UserIdentityData.fromMap(Map<String, dynamic> map) => UserIdentityData(
    peerId: map['peer_id'] as String,
    displayName: map['display_name'] as String,
    publicKey: Uint8List.fromList(map['public_key'] as List<int>),
    privateKey: map['private_key'] != null
        ? Uint8List.fromList(map['private_key'] as List<int>)
        : null,
    createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
  );

  UserIdentityData copyWith({
    String? displayName,
    Uint8List? privateKey,
  }) => UserIdentityData(
    peerId: peerId,
    displayName: displayName ?? this.displayName,
    publicKey: publicKey,
    privateKey: privateKey ?? this.privateKey,
    createdAt: createdAt,
  );
}
