import 'dart:typed_data';

enum LoanStatus {
  pending,
  approved,
  rejected,
  disbursed,
  repaying,
  completed,
  defaulted,
}

class LoanRequest {
  final String id;
  final String groupId;
  final String borrowerPeerId;
  final double requestedAmount;
  final double approvedAmount;
  final double interestRate;
  final int termWeeks;
  final String? reason;
  final LoanStatus status;
  final DateTime requestedAt;
  final DateTime? approvedAt;
  final String? approvedByPeerId;
  final DateTime? disbursedAt;
  final DateTime? completedAt;
  final DateTime? defaultedAt;
  final Uint8List borrowerSignature;
  final Uint8List? approverSignature;

  const LoanRequest({
    required this.id,
    required this.groupId,
    required this.borrowerPeerId,
    required this.requestedAmount,
    this.approvedAmount = 0,
    required this.interestRate,
    required this.termWeeks,
    this.reason,
    this.status = LoanStatus.pending,
    required this.requestedAt,
    this.approvedAt,
    this.approvedByPeerId,
    this.disbursedAt,
    this.completedAt,
    this.defaultedAt,
    required this.borrowerSignature,
    this.approverSignature,
  });

  double get totalWithInterest => approvedAmount * (1 + interestRate);
  double get weeklyPayment => totalWithInterest / termWeeks;
  bool get isPending => status == LoanStatus.pending;
  bool get isActive => status == LoanStatus.disbursed || status == LoanStatus.repaying;

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'borrowerPeerId': borrowerPeerId,
    'requestedAmount': requestedAmount,
    'approvedAmount': approvedAmount,
    'interestRate': interestRate,
    'termWeeks': termWeeks,
    'reason': reason,
    'status': status.name,
    'requestedAt': requestedAt.toIso8601String(),
    'approvedAt': approvedAt?.toIso8601String(),
    'approvedByPeerId': approvedByPeerId,
    'disbursedAt': disbursedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'defaultedAt': defaultedAt?.toIso8601String(),
    'borrowerSignature': borrowerSignature,
    'approverSignature': approverSignature,
  };

  factory LoanRequest.fromJson(Map<String, dynamic> json) => LoanRequest(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    borrowerPeerId: json['borrowerPeerId'] as String,
    requestedAmount: (json['requestedAmount'] as num).toDouble(),
    approvedAmount: (json['approvedAmount'] as num?)?.toDouble() ?? 0,
    interestRate: (json['interestRate'] as num).toDouble(),
    termWeeks: json['termWeeks'] as int,
    reason: json['reason'] as String?,
    status: LoanStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => LoanStatus.pending,
    ),
    requestedAt: DateTime.parse(json['requestedAt'] as String),
    approvedAt: json['approvedAt'] != null
        ? DateTime.parse(json['approvedAt'] as String)
        : null,
    approvedByPeerId: json['approvedByPeerId'] as String?,
    disbursedAt: json['disbursedAt'] != null
        ? DateTime.parse(json['disbursedAt'] as String)
        : null,
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null,
    defaultedAt: json['defaultedAt'] != null
        ? DateTime.parse(json['defaultedAt'] as String)
        : null,
    borrowerSignature: Uint8List.fromList((json['borrowerSignature'] as List).cast<int>()),
    approverSignature: json['approverSignature'] != null
        ? Uint8List.fromList((json['approverSignature'] as List).cast<int>())
        : null,
  );
}
