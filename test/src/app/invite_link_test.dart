import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/invite_link.dart';

InviteLink _link() => InviteLink(
  groupId: 'g1',
  groupCid: 'cid-1',
  groupTopic: 'vbank/group/g1',
  inviterPeerId: 'owner',
  inviterName: 'Owner',
  inviteId: 'id-1',
  secret: Uint8List.fromList(List<int>.generate(32, (i) => i)),
  nonce: Uint8List.fromList(List<int>.generate(16, (i) => 255 - i)),
  expiresAt: DateTime.utc(2026, 2, 1),
);

void main() {
  group('InviteLink', () {
    test('round-trips through encode and parse', () {
      final InviteLink original = _link();
      final String encoded = original.encode();
      expect(encoded.startsWith('vbank://join?'), isTrue);
      final InviteLink? parsed = InviteLink.tryParse(encoded);
      expect(parsed, isNotNull);
      expect(parsed!.groupId, 'g1');
      expect(parsed.groupCid, 'cid-1');
      expect(parsed.groupTopic, 'vbank/group/g1');
      expect(parsed.inviterPeerId, 'owner');
      expect(parsed.inviterName, 'Owner');
      expect(parsed.inviteId, 'id-1');
      expect(parsed.secret, original.secret);
      expect(parsed.nonce, original.nonce);
      expect(parsed.expiresAt, DateTime.utc(2026, 2, 1));
    });

    test('rejects garbage, wrong scheme and version', () {
      expect(InviteLink.tryParse(''), isNull);
      expect(InviteLink.tryParse('https://example.com/x'), isNull);
      expect(InviteLink.tryParse('vbank://join?!!!'), isNull);
      expect(InviteLink.tryParse('vbank://join?e30'), isNull);
    });

    test('reports expiry', () {
      final InviteLink link = _link();
      expect(link.isExpiredAt(DateTime.utc(2026, 1, 1)), isFalse);
      expect(link.isExpiredAt(DateTime.utc(2026, 3, 1)), isTrue);
    });
  });
}
