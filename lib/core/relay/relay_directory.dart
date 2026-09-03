import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// The relay every copy of vBank knows about. Members can add more (Settings →
/// Sync status → Relay server) and can switch this one off.
///
/// Only the hostname ships in the app. The relay's peer id — the `/p2p/…` part
/// of its address — is published by the operator as a DNS TXT record, the
/// libp2p `dnsaddr` convention:
///
///   _dnsaddr.vbank.localhost.co.zm.  TXT  "dnsaddr=/dns4/vbank.localhost.co.zm/tcp/4001/p2p/12D3KooW…"
///
/// so the relay can be rotated or moved without an app update.
const List<String> kBuiltInRelayHosts = ['vbank.localhost.co.zm'];

/// Resolves `dnsaddr` TXT records for the built-in relay hosts over
/// DNS-over-HTTPS (plain `dart:io` cannot query TXT). Results are cached in
/// memory for [ttl]; callers persist the last good answer so a phone that
/// starts offline still knows where the relay was.
class RelayDirectory {
  RelayDirectory({Future<List<String>> Function(String name)? txtLookup, this.ttl = const Duration(hours: 1)})
      : _txtLookup = txtLookup ?? _dohTxt;

  final Future<List<String>> Function(String name) _txtLookup;
  final Duration ttl;
  final _cache = <String, (DateTime, List<String>)>{};

  /// Multiaddrs (with `/p2p/`) for [host], newest lookup first; empty when the
  /// record is missing or the network is down.
  Future<List<String>> resolve(String host) async {
    final hit = _cache[host];
    if (hit != null && DateTime.now().difference(hit.$1) < ttl) return hit.$2;
    List<String> addrs = const [];
    try {
      final records = [
        ...await _txtLookup('_dnsaddr.$host'),
      ];
      addrs = parseDnsaddr(records, host: host);
    } catch (_) {
      // Offline or DoH blocked: caller falls back to its persisted copy.
    }
    if (addrs.isNotEmpty) _cache[host] = (DateTime.now(), addrs);
    return addrs;
  }

  /// `dnsaddr=/dns4/host/tcp/4001/p2p/Qm…` records → multiaddrs. Records that
  /// do not name a peer are ignored; a bare `/p2p/Qm…` is completed with
  /// [host] and port 4001.
  static List<String> parseDnsaddr(Iterable<String> txtRecords, {required String host}) {
    final out = <String>[];
    for (var r in txtRecords) {
      r = r.trim();
      if (r.startsWith('"') && r.endsWith('"')) r = r.substring(1, r.length - 1);
      if (!r.startsWith('dnsaddr=')) continue;
      var addr = r.substring('dnsaddr='.length).trim();
      if (!addr.contains('/p2p/')) continue;
      if (addr.startsWith('/p2p/')) addr = '/dns4/$host/tcp/4001$addr';
      if (!out.contains(addr)) out.add(addr);
    }
    return out;
  }

  /// TXT lookup over DNS-over-HTTPS (Cloudflare, then Google), JSON API.
  static Future<List<String>> _dohTxt(String name) async {
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 8);
    try {
      for (final base in const ['https://cloudflare-dns.com/dns-query', 'https://dns.google/resolve']) {
        try {
          final uri = Uri.parse('$base?name=${Uri.encodeQueryComponent(name)}&type=TXT');
          final req = await client.getUrl(uri);
          req.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
          final res = await req.close().timeout(const Duration(seconds: 10));
          if (res.statusCode != 200) continue;
          final body = jsonDecode(await res.transform(utf8.decoder).join()) as Map<String, dynamic>;
          final answers = (body['Answer'] as List?) ?? const [];
          return [for (final a in answers) if (a is Map && a['type'] == 16) '${a['data']}'];
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
