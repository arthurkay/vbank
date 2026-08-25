import 'dart:typed_data';

class OwnershipTransfer {
  final String id;
  final String groupId;
  final String fromPeerId;
  final String toPeerId;
  final DateTime transferredAt;
  final Uint8List oldOwnerSignature;
  final Uint8List newOwnerSignature;

  const OwnershipTransfer({
    required this.id,
    required this.groupId,
    required this.fromPeerId,
    required this.toPeerId,
    required this.transferredAt,
    required this.oldOwnerSignature,
    required this.newOwnerSignature,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'fromPeerId': fromPeerId,
    'toPeerId': toPeerId,
    'transferredAt': transferredAt.toIso8601String(),
    'oldOwnerSignature': oldOwnerSignature,
    'newOwnerSignature': newOwnerSignature,
  };

  factory OwnershipTransfer.fromJson(Map<String, dynamic> json) => OwnershipTransfer(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    fromPeerId: json['fromPeerId'] as String,
    toPeerId: json['toPeerId'] as String,
    transferredAt: DateTime.parse(json['transferredAt'] as String),
    oldOwnerSignature: Uint8List.fromList((json['oldOwnerSignature'] as List).cast<int>()),
    newOwnerSignature: Uint8List.fromList((json['newOwnerSignature'] as List).cast<int>()),
  );
}
