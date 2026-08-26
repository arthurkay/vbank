import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/ipfs/sync_ledger.dart';

import 'helpers/test_db.dart';

void main() {
  setUp(useInMemoryDatabase);
  tearDown(closeTestDatabase);

  test('records CIDs newest-first, once, per group', () async {
    final ledger = SyncLedger();
    await ledger.record('g1', 'bafy1');
    await ledger.record('g1', 'bafy2');
    await ledger.record('g1', 'bafy1');
    await ledger.record('g2', 'bafyZ');
    expect(await ledger.cidsFor('g1'), ['bafy2', 'bafy1']);
    expect(await ledger.has('g1', 'bafy2'), isTrue);
    expect(await ledger.has('g2', 'bafy2'), isFalse);
    expect(await ledger.cidsFor('g3'), isEmpty);
  });
}
