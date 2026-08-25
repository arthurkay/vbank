import 'dart:typed_data';

enum TransactionType {
  contribution,
  loan,
  repayment,
  withdrawal,
  fee,
  penalty,
  reversal,
}

enum TransactionStatus { confirmed, reversed }

class Transaction {
  final String id;
  final String groupId;
  final String fromPeerId;
  final String toPeerId;
  final TransactionType type;
  final double amount;
  final String currency;
  final String? note;
  final DateTime timestamp;
  final int sequenceNumber;
  final Uint8List senderSignature;

  /// The owner/admin who recorded and signed this transaction. For a
  /// contribution this is normally *not* [fromPeerId] (the contributing
  /// member) — DESIGN_PLAN §13 makes members read-only.
  final String authorPeerId;

  /// Repayments/disbursements reference the loan they belong to.
  final String? loanId;
  final TransactionStatus status;

  const Transaction({
    required this.id,
    required this.groupId,
    required this.fromPeerId,
    required this.toPeerId,
    required this.type,
    required this.amount,
    this.currency = 'ZMW',
    this.note,
    required this.timestamp,
    required this.sequenceNumber,
    required this.senderSignature,
    this.status = TransactionStatus.confirmed,
    String? authorPeerId,
    this.loanId,
  }) : authorPeerId = authorPeerId ?? fromPeerId;

  bool get isContribution => type == TransactionType.contribution;
  bool get isLoan => type == TransactionType.loan;
  bool get isRepayment => type == TransactionType.repayment;
  bool get isWithdrawal => type == TransactionType.withdrawal;
  bool get isPenalty => type == TransactionType.penalty;
  bool get isReversal => type == TransactionType.reversal;

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'fromPeerId': fromPeerId,
    'toPeerId': toPeerId,
    'type': type.name,
    'amount': amount,
    'currency': currency,
    'note': note,
    'timestamp': timestamp.toIso8601String(),
    'sequenceNumber': sequenceNumber,
    'senderSignature': senderSignature,
    'status': status.name,
    'authorPeerId': authorPeerId,
    'loanId': loanId,
  };

  factory Transaction.fromJson(Map<String, dynamic> json) => Transaction(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    fromPeerId: json['fromPeerId'] as String,
    toPeerId: json['toPeerId'] as String,
    type: TransactionType.values.firstWhere(
      (t) => t.name == json['type'],
    ),
    amount: (json['amount'] as num).toDouble(),
    currency: json['currency'] as String? ?? 'ZMW',
    note: json['note'] as String?,
    timestamp: DateTime.parse(json['timestamp'] as String),
    sequenceNumber: json['sequenceNumber'] as int,
    senderSignature: Uint8List.fromList((json['senderSignature'] as List).cast<int>()),
    status: TransactionStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => TransactionStatus.confirmed,
    ),
    authorPeerId: json['authorPeerId'] as String?,
    loanId: json['loanId'] as String?,
  );
}
