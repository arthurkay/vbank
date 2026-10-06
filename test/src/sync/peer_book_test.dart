import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/sync/peer_book.dart';

import 'fakes.dart';

void main() {
  group('PeerBook', () {
    test('remembers newest-first, deduplicated and capped', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final PeerBook book = PeerBook(settings);
      const String a1 = '/ip4/1.1.1.1/tcp/4001/p2p/QmA';
      const String a2 = '/ip4/2.2.2.2/tcp/4001/p2p/QmB';

      await book.remember('g', [a1]);
      await book.remember('g', [a2, a1]);

      expect(await book.addrsFor('g'), [a2, a1]);
    });

    test('a new peer id at a known address replaces the old entry', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final PeerBook book = PeerBook(settings);
      const String oldAddr = '/ip4/1.1.1.1/tcp/4001/p2p/QmOld';
      const String newAddr = '/ip4/1.1.1.1/tcp/4001/p2p/QmNew';

      await book.remember('g', [oldAddr]);
      await book.remember('g', [newAddr]);

      // Same transport: the stale id is gone everywhere.
      expect(await book.addrsFor('g'), [newAddr]);
    });

    test('stale transports learned elsewhere are pruned', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final PeerBook book = PeerBook(settings);
      const String stale = '/ip4/1.1.1.1/tcp/4001/p2p/QmOld';

      await book.remember('g-1', [stale]);
      await book.remember('g-2', ['/ip4/1.1.1.1/tcp/4001/p2p/QmNew']);

      expect(await book.addrsFor('g-1'), isEmpty);
    });

    test('ignores junk and skips the excluded peer', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final PeerBook book = PeerBook(settings);

      await book.remember('g', ['', 'no-p2p-here']);
      expect(await book.addrsFor('g'), isEmpty);

      await book.remember(
        'g',
        ['/ip4/1.1.1.1/tcp/4001/p2p/QmA'],
        exceptPeerId: 'QmA',
      );
      expect(await book.addrsFor('g'), isEmpty);
    });

    test('forgetAddr drops one, forget drops the group', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final PeerBook book = PeerBook(settings);
      const String a1 = '/ip4/1.1.1.1/tcp/4001/p2p/QmA';
      const String a2 = '/ip4/2.2.2.2/tcp/4001/p2p/QmB';
      await book.remember('g', [a1, a2]);

      await book.forgetAddr('g', a1);
      expect(await book.addrsFor('g'), [a2]);

      await book.forgetAddr('g', a1);
      await book.forget('g');
      expect(await book.addrsFor('g'), isEmpty);
    });

    test('mergeForInvite prefers own, one per transport, capped', () {
      expect(
        PeerBook.mergeForInvite(
          ['/ip4/1.1.1.1/tcp/4001/p2p/QmOwn'],
          [
            '/ip4/1.1.1.1/tcp/4001/p2p/QmSameTransport',
            '/ip4/2.2.2.2/tcp/4001/p2p/QmB',
            'junk',
          ],
        ),
        [
          '/ip4/1.1.1.1/tcp/4001/p2p/QmOwn',
          '/ip4/2.2.2.2/tcp/4001/p2p/QmB',
        ],
      );
      expect(
        PeerBook.mergeForInvite(
          [
            '/ip4/1.1.1.1/tcp/4001/p2p/Qm1',
            '/ip4/2.2.2.2/tcp/4001/p2p/Qm2',
            '/ip4/3.3.3.3/tcp/4001/p2p/Qm3',
          ],
          ['/ip4/4.4.4.4/tcp/4001/p2p/Qm4', '/ip4/5.5.5.5/tcp/4001/p2p/Qm5'],
          max: 2,
        ),
        hasLength(2),
      );
    });

    test('unreadable transports fail open, not closed', () async {
      // Without the transport map staleness cannot be checked; dropping
      // every address would lose all peers on a settings hiccup, while a
      // stale dial merely fails its handshake. Matches legacy behavior.
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final PeerBook book = PeerBook(settings);
      const String addr = '/ip4/1.1.1.1/tcp/4001/p2p/QmA';
      settings.store['peers.g'] = Uint8List.fromList(
        utf8.encode('["$addr"]'),
      );
      settings.failOn.add('peers.transports');

      expect(await book.addrsFor('g'), [addr]);
    });

    test('corrupt transport maps fail open too', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final PeerBook book = PeerBook(settings);
      const String addr = '/ip4/1.1.1.1/tcp/4001/p2p/QmA';
      await book.remember('g', [addr]);
      settings.store[PeerBook.transportsKey] = Uint8List.fromList(
        utf8.encode('{broken'),
      );

      expect(await book.addrsFor('g'), [addr]);
    });

    test('address parts split at the peer segment', () {
      const String addr = '/ip4/1.2.3.4/tcp/4001/p2p/QmX';

      expect(PeerBook.transportOf(addr), '/ip4/1.2.3.4/tcp/4001');
      expect(PeerBook.peerIdOf(addr), 'QmX');
      expect(PeerBook.keyFor('g'), 'peers.g');
    });
  });
}
