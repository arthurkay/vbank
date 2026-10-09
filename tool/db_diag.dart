import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:sqlite3/sqlite3.dart';

/// Read-only diagnostic over a COPY of the desktop database.
///
/// Usage: set the VBANK_DB_SECRET environment variable to the base64
/// device secret, then run dart run tool/db_diag.dart.
/// Prints groups, members, recent transactions, ledger heads and relay
/// settings. Never touches the live file: it copies to a temp dir first,
/// and the secret travels by environment, never argv.
Future<void> main() async {
  final String? encoded = Platform.environment['VBANK_DB_SECRET'];
  if (encoded == null || encoded.isEmpty) {
    stderr.writeln('usage: VBANK_DB_SECRET=<base64> dart run tool/db_diag.dart');
    exit(64);
  }
  final Uint8List secret = Uint8List.fromList(base64Decode(encoded.trim()));
  final Hkdf hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  final SecretKey key = await hkdf.deriveKey(
    secretKey: SecretKey(secret),
    info: 'vbank-db-v1'.codeUnits,
    nonce: List<int>.filled(16, 0),
  );
  final List<int> bytes = await key.extractBytes();
  final StringBuffer hex = StringBuffer();
  for (final int b in bytes) {
    hex.write(b.toRadixString(16).padLeft(2, '0'));
  }

  const String live =
      '/home/arthur/.local/share/zm.co.tickethost.vbank/vbank.db';
  final Directory tmp = await Directory.systemTemp.createTemp('vbank-diag-');
  final String copy = '${tmp.path}/vbank.db';
  await File(live).copy(copy);
  final Database db = sqlite3.open(copy);
  try {
    db
      ..execute("PRAGMA cipher = 'sqlcipher'")
      ..execute('PRAGMA legacy = 4')
      ..execute('PRAGMA key = "x\'$hex\'"');
    final ResultSet probe = db.select('SELECT count(*) AS n FROM groups');
    stdout.writeln('groups table reachable, rows=${probe.first['n']}');
    for (final Row g in db.select(
      'SELECT id, name, sequence_number, cid FROM groups',
    )) {
      stdout.writeln(
        'GROUP ${g['id']} name=${g['name']} seq=${g['sequence_number']} '
        'cid=${g['cid']}',
      );
      for (final Row m in db.select(
        'SELECT peer_id, name, role, status FROM members WHERE group_id = ?',
        [g['id']],
      )) {
        stdout.writeln(
          '  MEMBER ${m['peer_id']} name=${m['name']} role=${m['role']} '
          'status=${m['status']}',
        );
      }
      for (final Row t in db.select(
        'SELECT id, type, amount, timestamp, synced FROM transactions '
        'WHERE group_id = ? ORDER BY timestamp DESC LIMIT 10',
        [g['id']],
      )) {
        stdout.writeln(
          '  TX ${t['id']} type=${t['type']} amount=${t['amount']} '
          'ts=${t['timestamp']} synced=${t['synced']}',
        );
      }
      for (final Row s in db.select(
        "SELECT key FROM settings WHERE key = 'ledger.${g['id']}'",
      )) {
        final Row? v = db
            .select('SELECT value FROM settings WHERE key = ?', [s['key']])
            .firstOrNull;
        if (v != null) {
          final List<dynamic> cids =
              jsonDecode(utf8.decode(v['value'] as Uint8List)) as List;
          stdout.writeln('  LEDGER n=${cids.length}');
          for (final Object? c in cids) {
            stdout.writeln('    $c');
          }
        }
      }
      for (final Row i in db.select(
        'SELECT id, used, expires_at FROM invites WHERE group_id = ?',
        [g['id']],
      )) {
        stdout.writeln(
          '  INVITE ${i['id']} used=${i['used']} expires=${i['expires_at']}',
        );
      }
    }
    for (final Row s in db.select('SELECT key, value FROM settings')) {
      final String k = s['key'] as String;
      if (k.startsWith('relay.') || k.startsWith('snapshot.at.')) {
        try {
          stdout.writeln('SET $k = ${utf8.decode(s['value'] as Uint8List)}');
        } catch (_) {
          stdout.writeln('SET $k = <${(s['value'] as Uint8List).length}B>');
        }
      } else {
        final Uint8List v = s['value'] as Uint8List;
        String preview;
        try {
          final String text = utf8.decode(v);
          preview = text.length <= 120 ? text : '${text.substring(0, 120)}…';
        } catch (_) {
          preview = '<${v.length}B binary>';
        }
        stdout.writeln('SET $k = $preview');
      }
    }
    try {
      for (final Row k in db.select(
        'SELECT group_id, version, created_at FROM group_key_history '
        'ORDER BY group_id, version',
      )) {
        stdout.writeln(
          'KEYHIST group=${k['group_id']} v=${k['version']} '
          'at=${k['created_at']}',
        );
      }
    } catch (e) {
      stdout.writeln('KEYHIST unavailable: $e');
    }
    try {
      for (final Row k in db.select(
        'SELECT name FROM sqlite_master WHERE type = \'table\'',
      )) {
        stdout.writeln('TABLE ${k['name']}');
      }
    } catch (_) {}
  } finally {
    db.close();
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  }
}
