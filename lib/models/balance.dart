class Balance {
  final String peerId;
  final String groupId;
  final double totalContributed;
  final double totalLoaned;
  final double totalRepaid;
  final double totalWithdrawn;
  final double totalPenalties;
  final double outstandingLoan;
  final double netBalance;
  final DateTime lastUpdated;

  const Balance({
    required this.peerId,
    required this.groupId,
    this.totalContributed = 0,
    this.totalLoaned = 0,
    this.totalRepaid = 0,
    this.totalWithdrawn = 0,
    this.totalPenalties = 0,
    this.outstandingLoan = 0,
    this.netBalance = 0,
    required this.lastUpdated,
  });

  double get availableBalance => netBalance - outstandingLoan;

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'groupId': groupId,
    'totalContributed': totalContributed,
    'totalLoaned': totalLoaned,
    'totalRepaid': totalRepaid,
    'totalWithdrawn': totalWithdrawn,
    'totalPenalties': totalPenalties,
    'outstandingLoan': outstandingLoan,
    'netBalance': netBalance,
    'lastUpdated': lastUpdated.toIso8601String(),
  };

  factory Balance.fromJson(Map<String, dynamic> json) => Balance(
    peerId: json['peerId'] as String,
    groupId: json['groupId'] as String,
    totalContributed: (json['totalContributed'] as num?)?.toDouble() ?? 0,
    totalLoaned: (json['totalLoaned'] as num?)?.toDouble() ?? 0,
    totalRepaid: (json['totalRepaid'] as num?)?.toDouble() ?? 0,
    totalWithdrawn: (json['totalWithdrawn'] as num?)?.toDouble() ?? 0,
    totalPenalties: (json['totalPenalties'] as num?)?.toDouble() ?? 0,
    outstandingLoan: (json['outstandingLoan'] as num?)?.toDouble() ?? 0,
    netBalance: (json['netBalance'] as num?)?.toDouble() ?? 0,
    lastUpdated: DateTime.parse(json['lastUpdated'] as String),
  );
}
