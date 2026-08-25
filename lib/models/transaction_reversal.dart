import 'dart:typed_data';

enum ReversalStatus { pending, approved, rejected }

class TransactionReversal {
  final String id;
  final String originalTransactionId;
  final String groupId;
  final String requestedByPeerId;
  final String? approvedByPeerId;
  final String reason;
  final ReversalStatus status;
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final Uint8List requesterSignature;
  final Uint8List? approverSignature;

  const TransactionReversal({
    required this.id,
    required this.originalTransactionId,
    required this.groupId,
    required this.requestedByPeerId,
    this.approvedByPeerId,
    required this.reason,
    this.status = ReversalStatus.pending,
    required this.requestedAt,
    this.resolvedAt,
    required this.requesterSignature,
    this.approverSignature,
  });

  bool get isPending => status == ReversalStatus.pending;
  bool get isApproved => status == ReversalStatus.approved;
  bool get isRejected => status == ReversalStatus.rejected;

  Map<String, dynamic> toJson() => {
    'id': id,
    'originalTransactionId': originalTransactionId,
    'groupId': groupId,
    'requestedByPeerId': requestedByPeerId,
    'approvedByPeerId': approvedByPeerId,
    'reason': reason,
    'status': status.name,
    'requestedAt': requestedAt.toIso8601String(),
    'resolvedAt': resolvedAt?.toIso8601String(),
    'requesterSignature': requesterSignature,
    'approverSignature': approverSignature,
  };

  factory TransactionReversal.fromJson(Map<String, dynamic> json) => TransactionReversal(
    id: json['id'] as String,
    originalTransactionId: json['originalTransactionId'] as String,
    groupId: json['groupId'] as String,
    requestedByPeerId: json['requestedByPeerId'] as String,
    approvedByPeerId: json['approvedByPeerId'] as String?,
    reason: json['reason'] as String,
    status: ReversalStatus.values.firstWhere(
      (s) => s.name == json['status'],
    ),
    requestedAt: DateTime.parse(json['requestedAt'] as String),
    resolvedAt: json['resolvedAt'] != null
        ? DateTime.parse(json['resolvedAt'] as String)
        : null,
    requesterSignature: Uint8List.fromList((json['requesterSignature'] as List).cast<int>()),
    approverSignature: json['approverSignature'] != null
        ? Uint8List.fromList((json['approverSignature'] as List).cast<int>())
        : null,
  );
}
