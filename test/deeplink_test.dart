import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/deeplink/deeplink_handler.dart';

void main() {
  group('DeepLinkHandler.parse', () {
    test('inviter addresses round-trip through the link', () {
      final link = DeepLinkHandler.buildJoinLink(
        groupId: 'G1',
        inviterPeerId: 'P1',
        groupCid: 'bafy1',
        inviteId: 'I1',
        inviteNonceB64: 'bm9uY2U=',
        inviterAddrs: ['/ip4/192.168.1.141/tcp/4001/p2p/P1', '/ip4/10.0.0.5/tcp/4001/p2p/P1'],
      );
      final r = DeepLinkHandler.parseString(link);
      expect(r.isJoin, isTrue);
      expect(r.inviterAddrs, ['/ip4/192.168.1.141/tcp/4001/p2p/P1', '/ip4/10.0.0.5/tcp/4001/p2p/P1']);
      expect(r.inviteNonceB64, 'bm9uY2U=', reason: 'base64 padding survives URL encoding');
    });

    test('links without addresses parse with an empty list', () {
      final r = DeepLinkHandler.parseString('vbank://join?group=G1&inviter=P1');
      expect(r.inviterAddrs, isEmpty);
    });

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

  test('a link with four member addresses round-trips and stays QR-sized', () {
    final addrs = List.generate(4, (i) => '/ip4/192.168.10.${i + 2}/tcp/4001/p2p/12D3KooW${'x' * 44}$i');
    final link = DeepLinkHandler.buildJoinLink(
      groupId: 'a1dfc2d2-6988-4bb2-9f38-0fa0d209d297',
      inviterPeerId: addrs.first.split('/p2p/').last,
      groupCid: 'bafkreib4war74cp6shsjl5ximm7ncaubc4luv7dpgqh6pwtkw4rxrchlpe',
      inviteId: 'a1dfc2d2-6988-4bb2-9f38-0fa0d209d298',
      inviteNonceB64: 'AAECAwQFBgcICQoLDA0ODw==',
      inviterAddrs: addrs,
    );
    final r = DeepLinkHandler.parseString(link);
    expect(r.inviterAddrs, addrs);
    // Any of the four can serve the snapshot; keep the QR readable (~v16).
    expect(link.length, lessThan(800), reason: 'link is ${link.length} chars');
  });
}
