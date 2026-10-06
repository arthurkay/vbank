import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/invites.dart';

import 'fixtures.dart';

void main() {
  group('Invite', () {
    final DateTime created = DateTime.utc(2026, 4, 1, 10);
    final DateTime expires = created.add(const Duration(days: 7));

    Invite testInvite({bool used = false}) => Invite(
          id: 'i-1',
          groupId: 'g-1',
          groupCid: 'bafkrei-test',
          groupTopic: 'vbank/group/g-1',
          inviterPeerId: 'alice',
          inviterName: 'Alice',
          wrappedKey: Uint8List.fromList(const [9, 9, 9]),
          createdAt: created,
          expiresAt: expires,
          used: used,
          nonce: Uint8List.fromList(const [7, 7]),
          inviterSignature: testSignature(),
        );

    test('validity is a pure function of the clock', () {
      final Invite invite = testInvite();
      final DateTime before = created.add(const Duration(days: 6));
      final DateTime after = created.add(const Duration(days: 8));

      expect(invite.isExpiredAt(before), isFalse);
      expect(invite.isExpiredAt(after), isTrue);
      expect(invite.isValidAt(before), isTrue);
      expect(invite.isValidAt(after), isFalse);
      expect(testInvite(used: true).isValidAt(before), isFalse);
      expect(invite.validate().isOk, isTrue);
    });

    test('rejects expiry at or before creation', () {
      final Invite bad = Invite(
        id: 'i',
        groupId: 'g',
        groupCid: 'cid',
        groupTopic: 't',
        inviterPeerId: 'a',
        inviterName: 'A',
        wrappedKey: Uint8List.fromList(const [1]),
        createdAt: created,
        expiresAt: created,
        nonce: Uint8List.fromList(const [1]),
        inviterSignature: testSignature(),
      );

      expect(bad.validate().failure, isA<ValidationFailure>());
    });

    test('consuming an invite never reverts', () {
      final Invite used = testInvite().copyWith(used: true);

      expect(used.used, isTrue);
      expect(used == testInvite(), isFalse);
    });
  });
}
