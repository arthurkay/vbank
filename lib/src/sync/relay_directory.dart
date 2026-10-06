import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../domain/repositories.dart';

/// The relays every copy of vBank knows about.
///
/// Only hostnames ship in the app. Each relay's peer id — the `/p2p/…` part
/// of its address — is published by its operator as a DNS TXT record (the
/// libp2p `dnsaddr` convention), so relays move and rotate without an app
/// update:
///
/// `  _dnsaddr.vbank.localhost.co.zm.  TXT  "dnsaddr=/dns4/…/tcp/4001/p2p/…"`.
final class RelayDirectory {
  /// TXT lookup, injectable for tests. Production does DNS-over-HTTPS
  /// (plain `dart:io` cannot query TXT).
  final Future<List<String>> Function(String name) _txtLookup;

  /// How long answers are trusted.
  final Duration ttl;

  /// Settings for persisting the last good answer: a phone starting
  /// offline still knows where the relay was.
  final SettingsRepository? settings;

  /// DNS-over-HTTPS endpoints tried in order; override for tests.
  final List<String> dohEndpoints;

  /// Creates a directory.
  RelayDirectory({
    Future<List<String>> Function(String name)? txtLookup,
    this.ttl = const Duration(hours: 1),
    this.settings,
    this.dohEndpoints = const [
      'https://cloudflare-dns.com/dns-query',
      'https://dns.google/resolve',
    ],
  }) : _txtLookup = txtLookup ?? ((String name) => _dohTxt(name, dohEndpoints));

  /// In-memory cache: host → (looked up at, addresses).
  final Map<String, (DateTime, List<String>)> _cache = {};

  /// Multiaddrs (with `/p2p/`) for [host], newest lookup first; empty when
  /// the record is missing or the network is down (callers fall back to
  /// the persisted answer via [loadKnown]).
  Future<List<String>> resolve(String host, {DateTime? now}) async {
    final DateTime at = (now ?? DateTime.now()).toUtc();
    final (DateTime, List<String>)? hit = _cache[host];
    if (hit != null && at.difference(hit.$1) < ttl) {
      return hit.$2;
    }
    List<String> addrs = const [];
    try {
      addrs = parseDnsaddr(await _txtLookup('_dnsaddr.$host'), host: host);
    } catch (_) {
      // Offline or DoH blocked: caller falls back to its persisted copy.
    }
    if (addrs.isNotEmpty) {
      _cache[host] = (at, addrs);
      await saveKnown(host, addrs);
    }
    return addrs;
  }

  /// Persists the last good answer for [host].
  Future<void> saveKnown(String host, List<String> addrs) async {
    await settings?.set(
      'relay.known.$host',
      Uint8List.fromList(utf8.encode(jsonEncode(addrs))),
    );
  }

  /// The persisted last-good answer for [host], or empty.
  Future<List<String>> loadKnown(String host) async {
    final backend = settings;
    if (backend == null) {
      return const [];
    }
    final result = await backend.get('relay.known.$host');
    if (result.isErr || result.value == null) {
      return const [];
    }
    try {
      return (jsonDecode(utf8.decode(result.value!)) as List).cast<String>();
    } catch (_) {
      return const [];
    }
  }

  /// `dnsaddr=/dns4/host/tcp/4001/p2p/Qm…` records → multiaddrs. Records
  /// that do not name a peer are ignored; a bare `/p2p/Qm…` is completed
  /// with [host] and port 4001.
  static List<String> parseDnsaddr(
    Iterable<String> txtRecords, {
    required String host,
  }) {
    final List<String> out = [];
    for (String r in txtRecords) {
      r = r.trim();
      if (r.startsWith('"') && r.endsWith('"')) {
        r = r.substring(1, r.length - 1);
      }
      if (!r.startsWith('dnsaddr=')) {
        continue;
      }
      String addr = r.substring('dnsaddr='.length).trim();
      if (!addr.contains('/p2p/')) {
        continue;
      }
      if (addr.startsWith('/p2p/')) {
        addr = '/dns4/$host/tcp/4001$addr';
      }
      if (!out.contains(addr)) {
        out.add(addr);
      }
    }
    return out;
  }

  /// TXT lookup over DNS-over-HTTPS JSON APIs, trying [bases] in order.
  static Future<List<String>> _dohTxt(
    String name,
    List<String> bases,
  ) async {
    final HttpClient client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final String base in bases) {
        try {
          final Uri uri = Uri.parse(
            '$base?name=${Uri.encodeQueryComponent(name)}&type=TXT',
          );
          final HttpClientRequest req = await client.getUrl(uri);
          req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
          final HttpClientResponse res = await req.close().timeout(
            const Duration(seconds: 10),
          );
          if (res.statusCode != 200) {
            continue;
          }
          final Map<String, dynamic> body =
              jsonDecode(await res.transform(utf8.decoder).join())
                  as Map<String, dynamic>;
          final List<Object?> answers =
              (body['Answer'] as List?)?.cast<Object?>() ?? const [];
          return [
            for (final Object? a in answers)
              if (a is Map && a['type'] == 16) '${a['data']}',
          ];
        } catch (_) {
          continue;
        }
      }
      throw const SocketException('DNS-over-HTTPS unavailable');
    } finally {
      client.close(force: true);
    }
  }
}
