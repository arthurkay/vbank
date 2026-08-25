import 'dart:typed_data';

class Invite {
  final String id;
  final String groupId;
  final String groupCid;
  final String groupTopic;
  final String inviterPeerId;
  final String inviterName;
  final Uint8List groupKey;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool used;
  final Uint8List nonce;
  final Uint8List inviterSignature;

  const Invite({
    required this.id,
    required this.groupId,
    required this.groupCid,
    required this.groupTopic,
    required this.inviterPeerId,
    required this.inviterName,
    required this.groupKey,
    required this.createdAt,
    required this.expiresAt,
    this.used = false,
    required this.nonce,
    required this.inviterSignature,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isValid => !used && !isExpired;

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'groupCid': groupCid,
    'groupTopic': groupTopic,
    'inviterPeerId': inviterPeerId,
    'inviterName': inviterName,
    'groupKey': groupKey,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'used': used,
    'nonce': nonce,
    'inviterSignature': inviterSignature,
  };

  factory Invite.fromJson(Map<String, dynamic> json) => Invite(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    groupCid: json['groupCid'] as String,
    groupTopic: json['groupTopic'] as String,
    inviterPeerId: json['inviterPeerId'] as String,
    inviterName: json['inviterName'] as String,
    groupKey: Uint8List.fromList((json['groupKey'] as List).cast<int>()),
    createdAt: DateTime.parse(json['createdAt'] as String),
    expiresAt: DateTime.parse(json['expiresAt'] as String),
    used: json['used'] as bool? ?? false,
    nonce: Uint8List.fromList((json['nonce'] as List).cast<int>()),
    inviterSignature: Uint8List.fromList((json['inviterSignature'] as List).cast<int>()),
  );
}
