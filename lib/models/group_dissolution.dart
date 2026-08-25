enum DissolutionStatus {
  initiating,
  settlingLoans,
  distributingFunds,
  completed,
}

class GroupDissolution {
  final String id;
  final String groupId;
  final String initiatedByPeerId;
  final DateTime initiatedAt;
  final DissolutionStatus status;
  final bool allLoansSettled;
  final bool fundsDistributed;
  final DateTime? completedAt;

  const GroupDissolution({
    required this.id,
    required this.groupId,
    required this.initiatedByPeerId,
    required this.initiatedAt,
    this.status = DissolutionStatus.initiating,
    this.allLoansSettled = false,
    this.fundsDistributed = false,
    this.completedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'groupId': groupId,
    'initiatedByPeerId': initiatedByPeerId,
    'initiatedAt': initiatedAt.toIso8601String(),
    'status': status.name,
    'allLoansSettled': allLoansSettled,
    'fundsDistributed': fundsDistributed,
    'completedAt': completedAt?.toIso8601String(),
  };

  factory GroupDissolution.fromJson(Map<String, dynamic> json) => GroupDissolution(
    id: json['id'] as String,
    groupId: json['groupId'] as String,
    initiatedByPeerId: json['initiatedByPeerId'] as String,
    initiatedAt: DateTime.parse(json['initiatedAt'] as String),
    status: DissolutionStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => DissolutionStatus.initiating,
    ),
    allLoansSettled: json['allLoansSettled'] as bool? ?? false,
    fundsDistributed: json['fundsDistributed'] as bool? ?? false,
    completedAt: json['completedAt'] != null
        ? DateTime.parse(json['completedAt'] as String)
        : null,
  );
}
