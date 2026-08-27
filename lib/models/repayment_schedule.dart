enum RepaymentStatus { pending, paid, overdue, waived }

extension RepaymentStatusLabel on RepaymentStatus {
  /// What the schedule row says. An unpaid instalment is simply *due* — "pending"
  /// read as if something were waiting for approval.
  String get label => switch (this) {
        RepaymentStatus.pending => 'Due',
        RepaymentStatus.paid => 'Paid',
        RepaymentStatus.overdue => 'Overdue',
        RepaymentStatus.waived => 'Waived',
      };
}

class RepaymentSchedule {
  final String id;
  final String loanId;
  final int installmentNumber;
  final double expectedAmount;
  final DateTime dueDate;
  final double paidAmount;
  final DateTime? paidAt;
  final bool isOverdue;
  final double penalty;
  final RepaymentStatus status;

  const RepaymentSchedule({
    required this.id,
    required this.loanId,
    required this.installmentNumber,
    required this.expectedAmount,
    required this.dueDate,
    this.paidAmount = 0,
    this.paidAt,
    this.isOverdue = false,
    this.penalty = 0,
    this.status = RepaymentStatus.pending,
  });

  double get remainingAmount => expectedAmount - paidAmount;
  bool get isPaid => status == RepaymentStatus.paid;
  bool get isPending => status == RepaymentStatus.pending;

  Map<String, dynamic> toJson() => {
    'id': id,
    'loanId': loanId,
    'installmentNumber': installmentNumber,
    'expectedAmount': expectedAmount,
    'dueDate': dueDate.toIso8601String(),
    'paidAmount': paidAmount,
    'paidAt': paidAt?.toIso8601String(),
    'isOverdue': isOverdue,
    'penalty': penalty,
    'status': status.name,
  };

  factory RepaymentSchedule.fromJson(Map<String, dynamic> json) => RepaymentSchedule(
    id: json['id'] as String,
    loanId: json['loanId'] as String,
    installmentNumber: json['installmentNumber'] as int,
    expectedAmount: (json['expectedAmount'] as num).toDouble(),
    dueDate: DateTime.parse(json['dueDate'] as String),
    paidAmount: (json['paidAmount'] as num?)?.toDouble() ?? 0,
    paidAt: json['paidAt'] != null
        ? DateTime.parse(json['paidAt'] as String)
        : null,
    isOverdue: json['isOverdue'] as bool? ?? false,
    penalty: (json['penalty'] as num?)?.toDouble() ?? 0,
    status: RepaymentStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => RepaymentStatus.pending,
    ),
  );
}
