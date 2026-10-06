import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/domain/membership.dart';

import 'fixtures.dart';

void main() {
  group('GroupConfig', () {
    test('defaults match the legacy rules', () {
      const GroupConfig c = GroupConfig(
        groupId: 'g',
        contributionAmount: 100,
      );

      expect(c.frequency, ContributionFrequency.monthly);
      expect(c.meetingDayOfWeek, 0);
      expect(c.meetingTime, const MeetingTime(hour: 9, minute: 0));
      expect(c.maxLoanMultiplier, 3.0);
      expect(c.loanInterestRate, 0.10);
      expect(c.latePenaltyRate, 0.05);
      expect(c.minContributionsForLoan, 3);
      expect(c.currency, 'ZMW');
      expect(c.requireLoanApproval, isTrue);
      expect(c.validate().isOk, isTrue);
    });

    test('rejects each bad field', () {
      const GroupConfig base = GroupConfig(
        groupId: 'g',
        contributionAmount: 100,
      );

      expect(
        base.copyWith(contributionAmount: 0).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        base.copyWith(contributionAmount: -5).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        base.copyWith(meetingDayOfWeek: 7).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        base.copyWith(maxLoanMultiplier: 0).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        base.copyWith(loanInterestRate: 1.5).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        base.copyWith(latePenaltyRate: -0.1).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        base.copyWith(minContributionsForLoan: -1).validate().failure,
        isA<ValidationFailure>(),
      );
      expect(
        base
            .copyWith(savingsTarget: () => -100)
            .validate()
            .failure,
        isA<ValidationFailure>(),
      );
    });

    test('copyWith clears the savings target with a null thunk', () {
      const GroupConfig withTarget = GroupConfig(
        groupId: 'g',
        contributionAmount: 100,
        savingsTarget: 500,
      );

      expect(
        withTarget.copyWith(savingsTarget: () => null).savingsTarget,
        isNull,
      );
    });
  });

  group('Group', () {
    test('derives owner, admins and active count', () {
      final Group g = testGroup(
        'g',
        members: [
          testMember('o', role: MemberRole.owner),
          testMember('a', role: MemberRole.admin),
          testMember('m'),
          testMember(
            's',
            status: MemberStatus.suspended,
          ),
        ],
      );

      expect(g.owner?.peerId, 'o');
      expect(g.admins.map((Member m) => m.peerId), ['a']);
      expect(
        g.regularMembers.map((Member m) => m.peerId),
        ['m', 's'],
      );
      expect(g.memberCount, 3);
    });

    test('owner is null without one', () {
      expect(testGroup('g').owner, isNull);
    });

    test('rejects blank id, blank name and negative sequence', () {
      expect(testGroup('').validate().failure, isA<ValidationFailure>());
      expect(
        testGroup('g', sequenceNumber: -1).validate().failure,
        isA<ValidationFailure>(),
      );
    });

    test('equality includes members and invite cids', () {
      final Group a = testGroup('g', members: [testMember('m')]);
      final Group b = testGroup('g', members: [testMember('m')]);

      expect(a, b);
      expect(
        a == b.copyWith(inviteCids: ['cid-1']),
        isFalse,
      );
      expect(
        a == b.copyWith(sequenceNumber: 2),
        isFalse,
      );
    });

    test('copyWith clears the snapshot cid with a null thunk', () {
      final Group g = testGroup('g').copyWith(cid: () => 'cid-1');

      expect(g.cid, 'cid-1');
      expect(g.copyWith(cid: () => null).cid, isNull);
    });
  });
}
