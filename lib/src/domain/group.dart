import 'dart:typed_data';

import 'core/bytes.dart';
import 'core/failure.dart';
import 'core/result.dart';
import 'meeting_time.dart';
import 'membership.dart';

/// Whether the group is running or wound up. Dissolved groups stay readable
/// as an archive but accept no new records.
enum GroupStatus {
  /// Running normally.
  active,

  /// Wound up; a read-only archive.
  dissolved,
}

/// How often contributions are due.
enum ContributionFrequency {
  /// Due every week.
  weekly,

  /// Due every two weeks.
  biweekly,

  /// Due every month.
  monthly,
}

/// The rules a group runs by.
final class GroupConfig {
  /// The group these rules belong to.
  final String groupId;

  /// Due per [frequency], in [currency].
  final double contributionAmount;

  /// How often contributions are due.
  final ContributionFrequency frequency;

  /// Meeting weekday, 0 = Sunday … 6 = Saturday.
  final int meetingDayOfWeek;

  /// Meeting wall-clock time.
  final MeetingTime meetingTime;

  /// Largest loan as a multiple of the borrower's contributions, e.g. `3.0`.
  final double maxLoanMultiplier;

  /// Per-loan interest as a fraction, e.g. `0.10` = 10%.
  final double loanInterestRate;

  /// Weekly penalty on overdue instalments as a fraction.
  final double latePenaltyRate;

  /// Contributions required before borrowing.
  final int minContributionsForLoan;

  /// ISO code, e.g. `'ZMW'`. See [CurrencyConfig].
  final String currency;

  /// Optional group savings goal, in [currency].
  final double? savingsTarget;

  /// True when an admin must approve each loan.
  final bool requireLoanApproval;

  /// Creates a group configuration.
  const GroupConfig({
    required this.groupId,
    required this.contributionAmount,
    this.frequency = ContributionFrequency.monthly,
    this.meetingDayOfWeek = 0,
    this.meetingTime = const MeetingTime(hour: 9, minute: 0),
    this.maxLoanMultiplier = 3.0,
    this.loanInterestRate = 0.10,
    this.latePenaltyRate = 0.05,
    this.minContributionsForLoan = 3,
    this.currency = 'ZMW',
    this.savingsTarget,
    this.requireLoanApproval = true,
  });

  /// Structural checks: positive amounts, weekday 0–6, rates within 0–1.
  Result<Unit> validate() {
    if (contributionAmount <= 0) {
      return const Err(ValidationFailure('contributionNotPositive'));
    }
    if (meetingDayOfWeek < 0 || meetingDayOfWeek > 6) {
      return const Err(ValidationFailure('meetingDayRange'));
    }
    if (maxLoanMultiplier <= 0) {
      return const Err(ValidationFailure('loanMultiplierNotPositive'));
    }
    if (loanInterestRate < 0 || loanInterestRate > 1) {
      return const Err(ValidationFailure('interestRateRange'));
    }
    if (latePenaltyRate < 0 || latePenaltyRate > 1) {
      return const Err(ValidationFailure('penaltyRateRange'));
    }
    if (minContributionsForLoan < 0) {
      return const Err(ValidationFailure('minContributionsNegative'));
    }
    if (savingsTarget != null && savingsTarget! <= 0) {
      return const Err(ValidationFailure('savingsTargetNotPositive'));
    }
    return const Ok(unit);
  }

  /// Copies this configuration, replacing the given fields.
  GroupConfig copyWith({
    double? contributionAmount,
    ContributionFrequency? frequency,
    int? meetingDayOfWeek,
    MeetingTime? meetingTime,
    double? maxLoanMultiplier,
    double? loanInterestRate,
    double? latePenaltyRate,
    int? minContributionsForLoan,
    String? currency,
    double? Function()? savingsTarget,
    bool? requireLoanApproval,
  }) =>
      GroupConfig(
        groupId: groupId,
        contributionAmount: contributionAmount ?? this.contributionAmount,
        frequency: frequency ?? this.frequency,
        meetingDayOfWeek: meetingDayOfWeek ?? this.meetingDayOfWeek,
        meetingTime: meetingTime ?? this.meetingTime,
        maxLoanMultiplier: maxLoanMultiplier ?? this.maxLoanMultiplier,
        loanInterestRate: loanInterestRate ?? this.loanInterestRate,
        latePenaltyRate: latePenaltyRate ?? this.latePenaltyRate,
        minContributionsForLoan:
            minContributionsForLoan ?? this.minContributionsForLoan,
        currency: currency ?? this.currency,
        savingsTarget:
            savingsTarget == null ? this.savingsTarget : savingsTarget(),
        requireLoanApproval: requireLoanApproval ?? this.requireLoanApproval,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is GroupConfig &&
          groupId == other.groupId &&
          contributionAmount == other.contributionAmount &&
          frequency == other.frequency &&
          meetingDayOfWeek == other.meetingDayOfWeek &&
          meetingTime == other.meetingTime &&
          maxLoanMultiplier == other.maxLoanMultiplier &&
          loanInterestRate == other.loanInterestRate &&
          latePenaltyRate == other.latePenaltyRate &&
          minContributionsForLoan == other.minContributionsForLoan &&
          currency == other.currency &&
          savingsTarget == other.savingsTarget &&
          requireLoanApproval == other.requireLoanApproval;

  @override
  int get hashCode => Object.hash(
        groupId,
        contributionAmount,
        frequency,
        meetingDayOfWeek,
        meetingTime,
        maxLoanMultiplier,
        loanInterestRate,
        latePenaltyRate,
        minContributionsForLoan,
        currency,
        savingsTarget,
        requireLoanApproval,
      );
}

/// A savings group: its rules, members and sync bookkeeping.
final class Group {
  /// Stable id, shared by every member's copy.
  final String id;

  /// Display name.
  final String name;

  /// The rules the group runs by.
  final GroupConfig config;

  /// Every known member, any status.
  final List<Member> members;

  /// CIDs of invites handed out; used to recognise consumed one-use invites.
  final List<String> inviteCids;

  /// True when joins wait for admin approval instead of landing instantly.
  final bool requireApproval;

  /// When the group was created.
  final DateTime createdAt;

  /// Bumped on every mutation; higher wins in conflict resolution.
  final int sequenceNumber;

  /// Running or wound up.
  final GroupStatus status;

  /// The owner's signature over the membership, proving provenance.
  final Uint8List ownerSignature;

  /// CID of the latest encrypted snapshot published to IPFS; null until the
  /// first successful publish. Rides in invite links so joiners can fetch it.
  final String? cid;

  /// Creates a group.
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

  /// The owner, if present.
  Member? get owner =>
      members.where((Member m) => m.role == MemberRole.owner).firstOrNull;

  /// Current admins.
  List<Member> get admins =>
      members.where((Member m) => m.role == MemberRole.admin).toList();

  /// Plain members, any status.
  List<Member> get regularMembers =>
      members.where((Member m) => m.role == MemberRole.member).toList();

  /// Heads counted for quorums: active members only.
  int get memberCount =>
      members.where((Member m) => m.status == MemberStatus.active).length;

  /// Structural checks: identifiers present, sequence non-negative.
  Result<Unit> validate() {
    if (id.isEmpty) {
      return const Err(ValidationFailure('groupIdEmpty'));
    }
    if (name.trim().isEmpty) {
      return const Err(ValidationFailure('groupNameEmpty'));
    }
    if (sequenceNumber < 0) {
      return const Err(ValidationFailure('sequenceNegative'));
    }
    return config.validate();
  }

  /// Copies this group, replacing the given fields.
  Group copyWith({
    String? name,
    GroupConfig? config,
    List<Member>? members,
    List<String>? inviteCids,
    bool? requireApproval,
    int? sequenceNumber,
    GroupStatus? status,
    Uint8List? ownerSignature,
    String? Function()? cid,
  }) =>
      Group(
        id: id,
        name: name ?? this.name,
        config: config ?? this.config,
        members: members ?? this.members,
        inviteCids: inviteCids ?? this.inviteCids,
        requireApproval: requireApproval ?? this.requireApproval,
        createdAt: createdAt,
        sequenceNumber: sequenceNumber ?? this.sequenceNumber,
        status: status ?? this.status,
        ownerSignature: ownerSignature ?? this.ownerSignature,
        cid: cid == null ? this.cid : cid(),
      );

  static bool _membersEqual(List<Member> a, List<Member> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  static bool _stringsEqual(List<String> a, List<String> b) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) {
        return false;
      }
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Group &&
          id == other.id &&
          name == other.name &&
          config == other.config &&
          _membersEqual(members, other.members) &&
          _stringsEqual(inviteCids, other.inviteCids) &&
          requireApproval == other.requireApproval &&
          createdAt == other.createdAt &&
          sequenceNumber == other.sequenceNumber &&
          status == other.status &&
          bytesEqual(ownerSignature, other.ownerSignature) &&
          cid == other.cid;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        config,
        Object.hashAll(members),
        Object.hashAll(inviteCids),
        requireApproval,
        createdAt,
        sequenceNumber,
        status,
        bytesHash(ownerSignature),
        cid,
      );
}
