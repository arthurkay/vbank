import 'dart:typed_data';

enum GroupStatus { active, dissolved }

class Group {
  final String id;
  final String name;
  final GroupConfig config;
  final List<Member> members;
  final List<String> inviteCids;
  final bool requireApproval;
  final DateTime createdAt;
  final int sequenceNumber;
  final GroupStatus status;
  final Uint8List ownerSignature;

  /// CID of the latest encrypted group snapshot published to IPFS (null until
  /// the first successful publish). Included in invite links so joiners can
  /// fetch the group's metadata.
  final String? cid;

  const Group({
    required this.id,
    required this.name,
    required this.config,
    this.members = const [],
    this.inviteCids = const [],
    this.requireApproval = false,
    required this.createdAt,
    this.sequenceNumber = 0,
    this.status = GroupStatus.active,
    required this.ownerSignature,
    this.cid,
  });

  Member? get owner => members.where((m) => m.role == MemberRole.owner).firstOrNull;
  List<Member> get admins => members.where((m) => m.role == MemberRole.admin).toList();
  List<Member> get regularMembers => members.where((m) => m.role == MemberRole.member).toList();
  int get memberCount => members.where((m) => m.status == MemberStatus.active).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'config': config.toJson(),
    'members': members.map((m) => m.toJson()).toList(),
    'inviteCids': inviteCids,
    'requireApproval': requireApproval,
    'createdAt': createdAt.toIso8601String(),
    'sequenceNumber': sequenceNumber,
    'status': status.name,
    'ownerSignature': ownerSignature,
  };

  factory Group.fromJson(Map<String, dynamic> json) => Group(
    id: json['id'] as String,
    name: json['name'] as String,
    config: GroupConfig.fromJson(json['config'] as Map<String, dynamic>),
    members: (json['members'] as List?)
        ?.map((m) => Member.fromJson(m as Map<String, dynamic>))
        .toList() ?? [],
    inviteCids: (json['inviteCids'] as List?)?.cast<String>() ?? [],
    requireApproval: json['requireApproval'] as bool? ?? false,
    createdAt: DateTime.parse(json['createdAt'] as String),
    sequenceNumber: json['sequenceNumber'] as int? ?? 0,
    status: GroupStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => GroupStatus.active,
    ),
    ownerSignature: Uint8List.fromList((json['ownerSignature'] as List).cast<int>()),
  );
}

enum ContributionFrequency { weekly, biweekly, monthly }

class GroupConfig {
  final String groupId;
  final double contributionAmount;
  final ContributionFrequency frequency;
  final int meetingDayOfWeek;
  final String meetingTime;
  final double maxLoanMultiplier;
  final double loanInterestRate;
  final double latePenaltyRate;
  final int minContributionsForLoan;
  final String currency;
  final double? savingsTarget;
  final bool requireLoanApproval;

  const GroupConfig({
    required this.groupId,
    required this.contributionAmount,
    this.frequency = ContributionFrequency.weekly,
    this.meetingDayOfWeek = 0,
    this.meetingTime = '09:00',
    this.maxLoanMultiplier = 3.0,
    this.loanInterestRate = 0.10,
    this.latePenaltyRate = 0.05,
    this.minContributionsForLoan = 3,
    this.currency = 'ZMW',
    this.savingsTarget,
    this.requireLoanApproval = true,
  });

  Map<String, dynamic> toJson() => {
    'groupId': groupId,
    'contributionAmount': contributionAmount,
    'frequency': frequency.name,
    'meetingDayOfWeek': meetingDayOfWeek,
    'meetingTime': meetingTime,
    'maxLoanMultiplier': maxLoanMultiplier,
    'loanInterestRate': loanInterestRate,
    'latePenaltyRate': latePenaltyRate,
    'minContributionsForLoan': minContributionsForLoan,
    'currency': currency,
    'savingsTarget': savingsTarget,
    'requireLoanApproval': requireLoanApproval,
  };

  factory GroupConfig.fromJson(Map<String, dynamic> json) => GroupConfig(
    groupId: json['groupId'] as String,
    contributionAmount: (json['contributionAmount'] as num).toDouble(),
    frequency: ContributionFrequency.values.firstWhere(
      (f) => f.name == json['frequency'],
      orElse: () => ContributionFrequency.weekly,
    ),
    meetingDayOfWeek: json['meetingDayOfWeek'] as int? ?? 0,
    meetingTime: json['meetingTime'] as String? ?? '09:00',
    maxLoanMultiplier: (json['maxLoanMultiplier'] as num?)?.toDouble() ?? 3.0,
    loanInterestRate: (json['loanInterestRate'] as num?)?.toDouble() ?? 0.10,
    latePenaltyRate: (json['latePenaltyRate'] as num?)?.toDouble() ?? 0.05,
    minContributionsForLoan: json['minContributionsForLoan'] as int? ?? 3,
    currency: json['currency'] as String? ?? 'ZMW',
    savingsTarget: (json['savingsTarget'] as num?)?.toDouble(),
    requireLoanApproval: json['requireLoanApproval'] as bool? ?? true,
  );
}

enum MemberRole { owner, admin, member }

/// `pending` = joined a group with `requireApproval` and awaiting an admin.
enum MemberStatus { active, suspended, removed, pending }

class Member {
  final String peerId;
  final String name;
  final MemberRole role;
  final DateTime joinedAt;
  final Uint8List publicKey;
  final MemberStatus status;
  final bool hasOutstandingLoan;

  const Member({
    required this.peerId,
    required this.name,
    this.role = MemberRole.member,
    required this.joinedAt,
    required this.publicKey,
    this.status = MemberStatus.active,
    this.hasOutstandingLoan = false,
  });

  Map<String, dynamic> toJson() => {
    'peerId': peerId,
    'name': name,
    'role': role.name,
    'joinedAt': joinedAt.toIso8601String(),
    'publicKey': publicKey,
    'status': status.name,
    'hasOutstandingLoan': hasOutstandingLoan,
  };

  factory Member.fromJson(Map<String, dynamic> json) => Member(
    peerId: json['peerId'] as String,
    name: json['name'] as String,
    role: MemberRole.values.firstWhere(
      (r) => r.name == json['role'],
      orElse: () => MemberRole.member,
    ),
    joinedAt: DateTime.parse(json['joinedAt'] as String),
    publicKey: Uint8List.fromList((json['publicKey'] as List).cast<int>()),
    status: MemberStatus.values.firstWhere(
      (s) => s.name == json['status'],
      orElse: () => MemberStatus.active,
    ),
    hasOutstandingLoan: json['hasOutstandingLoan'] as bool? ?? false,
  );
}
