import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/deeplink/deeplink_handler.dart';

void main() {
  group('DeepLinkHandler.parse', () {
    test('valid join link', () {
      final r = DeepLinkHandler.parseString('vbank://join?group=G1&inviter=P1');
      expect(r.type, DeepLinkType.joinGroup);
      expect(r.groupId, 'G1');
      expect(r.inviterPeerId, 'P1');
    });

    test('join link with empty values is an error, not a join', () {
      final r = DeepLinkHandler.parseString('vbank://join?group=&inviter=');
      expect(r.type, DeepLinkType.error);
    });

    test('join link missing inviter is an error', () {
      final r = DeepLinkHandler.parseString('vbank://join?group=G1');
      expect(r.type, DeepLinkType.error);
    });

    test('malformed percent-escape does not throw', () {
      final r = DeepLinkHandler.parseString('vbank://join?group=%FF&inviter=x');
      expect(r.type, DeepLinkType.error);
      expect(r.error, contains('Malformed'));
    });

    test('restore link without backup id is allowed', () {
      final r = DeepLinkHandler.parseString('vbank://restore');
      expect(r.type, DeepLinkType.restoreBackup);
      expect(r.backupId, isNull);
    });

    test('restore link with backup id', () {
      final r = DeepLinkHandler.parseString('vbank://restore?backup=B1');
      expect(r.backupId, 'B1');
    });

    test('foreign scheme is unknown', () {
      expect(DeepLinkHandler.parseString('https://example.com').type, DeepLinkType.unknown);
    });

    test('unknown host is unknown', () {
      expect(DeepLinkHandler.parseString('vbank://foo').type, DeepLinkType.unknown);
    });

    test('garbage is an error', () {
      expect(DeepLinkHandler.parseString('::::').type, DeepLinkType.error);
    });

    test('buildJoinLink round-trips group, inviter and snapshot cid', () {
      final link = DeepLinkHandler.buildJoinLink(
        groupId: '4e6b4016-d416-48d5-9e24-108e1db7b59a',
        inviterPeerId: 'vbank_298e8145-705a-5808-9b0a-0c0d144c25f9',
        groupCid: 'bafkreib5p6aszhjfsuu63omr4thpdkgqqx6cxny5a7x3fsly5dj54uzdc4',
      );
      expect(link, startsWith('vbank://join?'));
      final r = DeepLinkHandler.parseString(link);
      expect(r.type, DeepLinkType.joinGroup);
      expect(r.groupId, '4e6b4016-d416-48d5-9e24-108e1db7b59a');
      expect(r.inviterPeerId, 'vbank_298e8145-705a-5808-9b0a-0c0d144c25f9');
      expect(r.groupCid, 'bafkreib5p6aszhjfsuu63omr4thpdkgqqx6cxny5a7x3fsly5dj54uzdc4');
    });

    test('old links without cid still parse (cid null)', () {
      final r = DeepLinkHandler.parseString('vbank://join?group=G1&inviter=P1');
      expect(r.type, DeepLinkType.joinGroup);
      expect(r.groupCid, isNull);
    });
  });
}
