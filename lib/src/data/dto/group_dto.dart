import '../../domain/core/failure.dart';
import '../../domain/core/result.dart';
import '../../domain/group.dart';
import '../../domain/meeting_time.dart';
import '../../domain/membership.dart';
import 'dto.dart';

/// Row mapping for `groups` (config flattened in) and `members`.
abstract final class GroupDto {
  /// Serializes [group] to a `groups` row.
  static Map<String, Object?> toRow(Group group) => {
        'id': group.id,
        'name': group.name,
        'require_approval': Dto.flagValue(group.requireApproval),
        'created_at': Dto.instantValue(group.createdAt),
        'sequence_number': group.sequenceNumber,
        'status': group.status.name,
        'owner_signature': group.ownerSignature,
        'cid': group.cid,
        'contribution_amount': group.config.contributionAmount,
        'frequency': group.config.frequency.name,
        'meeting_day_of_week': group.config.meetingDayOfWeek,
        'meeting_time': group.config.meetingTime.format(),
        'max_loan_multiplier': group.config.maxLoanMultiplier,
        'loan_interest_rate': group.config.loanInterestRate,
        'late_penalty_rate': group.config.latePenaltyRate,
        'min_contributions_for_loan': group.config.minContributionsForLoan,
        'currency': group.config.currency,
        'savings_target': group.config.savingsTarget,
        'require_loan_approval':
            Dto.flagValue(group.config.requireLoanApproval),
      };

  /// Parses a `groups` row. Members ride separately via [MemberDto].
  static Result<Group> fromRow(Map<String, Object?> row) {
    try {
      final Result<MeetingTime> time = MeetingTime.parse(
        Dto.text(row, 'meeting_time'),
      );
      if (time.isErr) {
        return const Err(ValidationFailure('dto.group.meetingTime'));
      }
      return Ok(
        Group(
          id: Dto.text(row, 'id'),
          name: Dto.text(row, 'name'),
          config: GroupConfig(
            groupId: Dto.text(row, 'id'),
            contributionAmount: Dto.real(row, 'contribution_amount'),
            frequency: Dto.enumeration(
              row,
              'frequency',
              ContributionFrequency.values,
            ),
            meetingDayOfWeek: Dto.integer(row, 'meeting_day_of_week'),
            meetingTime: time.value,
            maxLoanMultiplier: Dto.real(row, 'max_loan_multiplier'),
            loanInterestRate: Dto.real(row, 'loan_interest_rate'),
            latePenaltyRate: Dto.real(row, 'late_penalty_rate'),
            minContributionsForLoan: Dto.integer(
              row,
              'min_contributions_for_loan',
            ),
            currency: Dto.text(row, 'currency'),
            savingsTarget: Dto.realOrNull(row, 'savings_target'),
            requireLoanApproval: Dto.flag(row, 'require_loan_approval'),
          ),
          requireApproval: Dto.flag(row, 'require_approval'),
          createdAt: Dto.instant(row, 'created_at'),
          sequenceNumber: Dto.integer(row, 'sequence_number'),
          status: Dto.enumeration(row, 'status', GroupStatus.values),
          ownerSignature: Dto.bytes(row, 'owner_signature'),
          cid: Dto.textOrNull(row, 'cid'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}

/// Row mapping for `members`.
abstract final class MemberDto {
  /// Serializes [member] of [groupId] to a `members` row.
  static Map<String, Object?> toRow(String groupId, Member member) => {
        'peer_id': member.peerId,
        'group_id': groupId,
        'name': member.name,
        'role': member.role.name,
        'joined_at': Dto.instantValue(member.joinedAt),
        'public_key': member.publicKey,
        'status': member.status.name,
        'has_outstanding_loan': Dto.flagValue(member.hasOutstandingLoan),
        'enc_key': member.encKey,
      };

  /// Parses a `members` row.
  static Result<Member> fromRow(Map<String, Object?> row) {
    try {
      return Ok(
        Member(
          peerId: Dto.text(row, 'peer_id'),
          name: Dto.text(row, 'name'),
          role: Dto.enumeration(row, 'role', MemberRole.values),
          joinedAt: Dto.instant(row, 'joined_at'),
          publicKey: Dto.bytes(row, 'public_key'),
          status: Dto.enumeration(row, 'status', MemberStatus.values),
          hasOutstandingLoan: Dto.flag(row, 'has_outstanding_loan'),
          encKey: Dto.bytesOrNull(row, 'enc_key'),
        ),
      );
    } catch (e) {
      return Err(StorageFailure(e));
    }
  }
}
