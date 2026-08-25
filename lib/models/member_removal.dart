import 'dart:typed_data';

enum RemovalAction { suspend, remove, settleAndRemove }

class MemberRemoval {
  final String id;
  final String groupId;
  final String removedPeerId;
  final String removedByPeerId;
  final String reason;
  final bool hasOutstandingLoan;
  final double outstandingAmount;
  final RemovalAction action;
  final DateTime removedAt;
  final Uint8List adminSignature;

  const MemberRemoval({
    required this.id,
    required this.groupId,
    required this.removedPeerId,
    required this.removedByPeerId,
    required this.reason,
    this.hasOutstandingLoan = false,
    this.outstandingAmount = 0,
    required this.action,
    required this.removedAt,
    required this.adminSignature,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'removedPeerId': removedPeerId,
    'removedByPeerId': removedByPeerId,
    'reason': reason,
    'hasOutstandingLoan': hasOutstandingLoan,
    'outstandingAmount': outstandingAmount,
    'action': action.name,
    'removedAt': removedAt.toIso8601String(),
    'adminSignature': adminSignature,
  };

  factory MemberRemoval.fromJson(Map<String, dynamic> json) => MemberRemoval(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    removedPeerId: json['removedPeerId'] as String,
    removedByPeerId: json['removedByPeerId'] as String,
    reason: json['reason'] as String,
    hasOutstandingLoan: json['hasOutstandingLoan'] as bool? ?? false,
    outstandingAmount: (json['outstandingAmount'] as num?)?.toDouble() ?? 0,
    action: RemovalAction.values.firstWhere(
      (a) => a.name == json['action'],
    ),
    removedAt: DateTime.parse(json['removedAt'] as String),
    adminSignature: Uint8List.fromList((json['adminSignature'] as List).cast<int>()),
  );
}
