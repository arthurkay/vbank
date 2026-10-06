import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/sync/relay_directory.dart';

import 'fakes.dart';

void main() {
  group('RelayDirectory', () {
    test('parseDnsaddr keeps only records that name a peer', () {
      final List<String> addrs = RelayDirectory.parseDnsaddr(
        [
          '"dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWAAA"',
          'dnsaddr=/ip4/203.0.113.7/tcp/4001/p2p/12D3KooWBBB',
          'dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001',
          'v=spf1 -all',
          'dnsaddr=/p2p/12D3KooWCCC',
          'dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWAAA',
        ],
        host: 'vbank.localhost.co.zm',
      );

      expect(addrs, [
        '/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWAAA',
        '/ip4/203.0.113.7/tcp/4001/p2p/12D3KooWBBB',
        '/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooWCCC',
      ]);
    });

    test('resolve caches for the ttl and swallows failures', () async {
      var calls = 0;
      final RelayDirectory dir = RelayDirectory(
        txtLookup: (String name) async {
          calls++;
          if (calls == 1) {
            throw Exception('offline');
          }
          expect(name, '_dnsaddr.relay.test');
          return ['dnsaddr=/dns4/relay.test/tcp/4001/p2p/12D3KooWXYZ'];
        },
        ttl: const Duration(minutes: 5),
      );

      expect(await dir.resolve('relay.test'), isEmpty);
      expect(
        await dir.resolve('relay.test'),
        ['/dns4/relay.test/tcp/4001/p2p/12D3KooWXYZ'],
      );
      expect(
        await dir.resolve('relay.test'),
        ['/dns4/relay.test/tcp/4001/p2p/12D3KooWXYZ'],
      );
      expect(calls, 2, reason: 'second answer served from cache');
    });

    test('cache expires after the ttl', () async {
      var calls = 0;
      DateTime now = DateTime.utc(2026, 1, 1);
      final RelayDirectory dir = RelayDirectory(
        txtLookup: (String name) async {
          calls++;
          return ['dnsaddr=/dns4/r.test/tcp/4001/p2p/12D3KooW$calls'];
        },
        ttl: const Duration(hours: 1),
      );

      await dir.resolve('r.test', now: now);
      now = now.add(const Duration(hours: 2));
      final List<String> addrs = await dir.resolve('r.test', now: now);

      expect(calls, 2);
      expect(addrs.single, contains('12D3KooW2'));
    });

    test('DNS-over-HTTPS lookup parses the JSON API', () async {
      final HttpServer server = await HttpServer.bind('127.0.0.1', 0);
      addTearDown(server.close);
      server.listen((HttpRequest req) async {
        req.response.headers.contentType = ContentType.json;
        if (req.uri.path == '/dns-query' &&
            req.uri.queryParameters['name'] == '_dnsaddr.r.test') {
          req.response.write(
            jsonEncode({
              'Answer': [
                {
                  'name': '_dnsaddr.r.test',
                  'type': 16,
                  'data':
                      '"dnsaddr=/dns4/r.test/tcp/4001/p2p/12D3KooWQ"',
                },
                {'name': '_dnsaddr.r.test', 'type': 1, 'data': '9.9.9.9'},
              ],
            }),
          );
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });
      final RelayDirectory dir = RelayDirectory(
        dohEndpoints: ['http://127.0.0.1:${server.port}/dns-query'],
      );

      expect(
        await dir.resolve('r.test'),
        ['/dns4/r.test/tcp/4001/p2p/12D3KooWQ'],
      );

      final RelayDirectory broken = RelayDirectory(
        dohEndpoints: ['http://127.0.0.1:${server.port}/missing'],
      );
      expect(await broken.resolve('r.test'), isEmpty);
    });

    test('last-good answers persist for offline starts', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final RelayDirectory dir = RelayDirectory(
        txtLookup: (String name) async => throw Exception('offline'),
        settings: settings,
      );
      await dir.saveKnown('r.test', ['/dns4/r.test/tcp/4001/p2p/12D3KooWA']);

      expect(await dir.loadKnown('r.test'), [
        '/dns4/r.test/tcp/4001/p2p/12D3KooWA',
      ]);
      expect(await dir.loadKnown('unknown.test'), isEmpty);

      final RelayDirectory noBackend = RelayDirectory(
        txtLookup: (String name) async => throw Exception('offline'),
      );
      expect(await noBackend.loadKnown('r.test'), isEmpty);
    });
  });
}
