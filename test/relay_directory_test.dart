import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/relay/relay_directory.dart';

/// Discovery of the built-in relay's address from `_dnsaddr` TXT records.
void main() {
  test('parseDnsaddr keeps only dnsaddr records that name a peer', () {
    final addrs = RelayDirectory.parseDnsaddr([
      '"dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWAAA"',
      'dnsaddr=/ip4/203.0.113.7/tcp/4001/p2p/12D3KooWBBB',
      'dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001', // no peer id: useless
      'v=spf1 -all', // unrelated TXT
      'dnsaddr=/p2p/12D3KooWCCC', // shorthand: host + default port filled in
      'dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWAAA', // duplicate
    ], host: 'vbank.localhost.co.zm');
    expect(addrs, [
      '/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWAAA',
      '/ip4/203.0.113.7/tcp/4001/p2p/12D3KooWBBB',
      '/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWCCC',
    ]);
  });

  test('resolve caches for the ttl and swallows lookup failures', () async {
    var calls = 0;
    final dir = RelayDirectory(
      txtLookup: (name) async {
        calls++;
        if (calls == 1) throw Exception('offline');
        expect(name, '_dnsaddr.relay.test');
        return ['dnsaddr=/dns4/relay.test/tcp/4001/p2p/12D3KooWXYZ'];
      },
      ttl: const Duration(minutes: 5),
    );
    expect(await dir.resolve('relay.test'), isEmpty, reason: 'first lookup failed');
    expect(await dir.resolve('relay.test'), ['/dns4/relay.test/tcp/4001/p2p/12D3KooWXYZ']);
    expect(await dir.resolve('relay.test'), ['/dns4/relay.test/tcp/4001/p2p/12D3KooWXYZ']);
    expect(calls, 2, reason: 'second answer served from cache');
  });

  test('built-in host list is the vBank relay', () {
    expect(kBuiltInRelayHosts, ['vbank.localhost.co.zm']);
  });

  test('DNS-over-HTTPS TXT lookup works against a public dnsaddr record', () async {
    // libp2p publishes its bootstrap list this way; a good smoke test of the
    // DoH path without depending on the vBank record being live yet.
    final addrs = await RelayDirectory().resolve('bootstrap.libp2p.io');
    expect(addrs, isNotEmpty);
    expect(addrs.first, contains('/p2p/'));
  }, tags: ['network']);
}
