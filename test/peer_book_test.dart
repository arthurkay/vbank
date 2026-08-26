import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/ipfs/peer_book.dart';

import 'helpers/test_db.dart';

/// The per-group address book that lets vBank nodes find each other without
/// relying on DHT/mDNS discovery.
void main() {
  setUp(useInMemoryDatabase);
  tearDown(closeTestDatabase);

  test('remembers addresses newest-first, deduplicated, per group', () async {
    final book = PeerBook();
    await book.remember('g1', ['/ip4/10.0.0.2/tcp/4001/p2p/A']);
    await book.remember('g1', ['/ip4/10.0.0.3/tcp/4001/p2p/B', '/ip4/10.0.0.2/tcp/4001/p2p/A']);
    await book.remember('g2', ['/ip4/10.0.0.9/tcp/4001/p2p/Z']);

    expect(await book.addrsFor('g1'), ['/ip4/10.0.0.3/tcp/4001/p2p/B', '/ip4/10.0.0.2/tcp/4001/p2p/A']);
    expect(await book.addrsFor('g2'), ['/ip4/10.0.0.9/tcp/4001/p2p/Z']);
    expect(await book.addrsFor('g3'), isEmpty);
  });

  test('ignores our own address and malformed entries', () async {
    final book = PeerBook();
    await book.remember('g1', ['/ip4/10.0.0.2/tcp/4001/p2p/ME', 'garbage', '  ', '/ip4/10.0.0.5/tcp/4001/p2p/X'],
        exceptPeerId: 'ME');
    expect(await book.addrsFor('g1'), ['/ip4/10.0.0.5/tcp/4001/p2p/X']);
  });

  test('caps the list so a chatty group cannot grow it without bound', () async {
    final book = PeerBook();
    for (var i = 0; i < 50; i++) {
      await book.remember('g1', ['/ip4/10.0.$i.1/tcp/4001/p2p/P$i']);
    }
    final addrs = await book.addrsFor('g1');
    expect(addrs.length, 32);
    expect(addrs.first, '/ip4/10.0.49.1/tcp/4001/p2p/P49', reason: 'newest kept');
  });

  test('a new peer id at a known address replaces the stale entry', () async {
    final book = PeerBook();
    await book.remember('g1', ['/ip4/10.0.0.2/tcp/4001/p2p/OLD', '/ip4/10.0.0.3/tcp/4001/p2p/B']);
    await book.remember('g1', ['/ip4/10.0.0.2/tcp/4001/p2p/NEW']);
    expect(await book.addrsFor('g1'), ['/ip4/10.0.0.2/tcp/4001/p2p/NEW', '/ip4/10.0.0.3/tcp/4001/p2p/B']);
  });

  test('a new peer id at a known address retires the old id in every group', () async {
    final book = PeerBook();
    await book.remember('g1', ['/ip4/10.0.0.2/tcp/4001/p2p/OLD']);
    await book.remember('g2', ['/ip4/10.0.0.2/tcp/4001/p2p/OLD', '/ip4/10.0.0.9/tcp/4001/p2p/Z']);
    await book.remember('g3', ['/ip4/10.0.0.2/tcp/4001/p2p/NEW']);
    expect(await book.addrsFor('g1'), isEmpty);
    expect(await book.addrsFor('g2'), ['/ip4/10.0.0.9/tcp/4001/p2p/Z']);
    expect(await book.addrsFor('g3'), ['/ip4/10.0.0.2/tcp/4001/p2p/NEW']);
  });

  test('forgetAddr drops a single address', () async {
    final book = PeerBook();
    await book.remember('g1', ['/ip4/10.0.0.2/tcp/4001/p2p/A', '/ip4/10.0.0.3/tcp/4001/p2p/B']);
    await book.forgetAddr('g1', '/ip4/10.0.0.3/tcp/4001/p2p/B');
    expect(await book.addrsFor('g1'), ['/ip4/10.0.0.2/tcp/4001/p2p/A']);
  });

  test('forget clears a group', () async {
    final book = PeerBook();
    await book.remember('g1', ['/ip4/10.0.0.2/tcp/4001/p2p/A']);
    await book.forget('g1');
    expect(await book.addrsFor('g1'), isEmpty);
  });
}
