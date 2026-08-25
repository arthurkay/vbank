import 'dart:typed_data';

// MemberRole / MemberStatus live in group.dart (single definition).

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

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'displayName': displayName,
    'publicKey': publicKey,
    'createdAt': createdAt.toIso8601String(),
  };

  factory UserIdentity.fromJson(Map<String, dynamic> json) => UserIdentity(
    peerId: json['peerId'] as String,
    displayName: json['displayName'] as String,
    publicKey: Uint8List.fromList((json['publicKey'] as List).cast<int>()),
    createdAt: DateTime.parse(json['createdAt'] as String),
  );
}
