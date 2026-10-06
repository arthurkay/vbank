import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/sync/ledger.dart';

import 'fakes.dart';

void main() {
  group('SyncLedger', () {
    test('records newest-first, deduplicated', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final SyncLedger ledger = SyncLedger(settings);

      await ledger.record('g', 'cid-1');
      await ledger.record('g', 'cid-2');
      await ledger.record('g', 'cid-1');

      expect(await ledger.cidsFor('g'), ['cid-2', 'cid-1']);
      expect(await ledger.has('g', 'cid-1'), isTrue);
      expect(await ledger.has('g', 'nope'), isFalse);
      expect(await ledger.cidsFor('other'), isEmpty);
    });

    test('caps at 5000 per group', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final SyncLedger ledger = SyncLedger(settings);

      for (var i = 0; i < SyncLedger.maxPerGroup + 10; i++) {
        await ledger.record('g', 'cid-$i');
      }

      final List<String> cids = await ledger.cidsFor('g');
      expect(cids, hasLength(SyncLedger.maxPerGroup));
      expect(cids.first, 'cid-${SyncLedger.maxPerGroup + 9}');
    });

    test('corrupt entries read as empty', () async {
      final MemorySettingsRepository settings = MemorySettingsRepository();
      final SyncLedger ledger = SyncLedger(settings);
      settings.store['ledger.g'] =
          Uint8List.fromList(utf8.encode('{not json'));

      expect(await ledger.cidsFor('g'), isEmpty);
    });
  });
}
