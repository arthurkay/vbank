import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/ipfs/pending_join.dart';
import 'package:vbank/models/group.dart';

import 'helpers/test_db.dart';

/// Joins parked while nobody from the group is reachable (see PendingJoin).
void main() {
  setUp(useInMemoryDatabase);
  tearDown(closeTestDatabase);

  PendingJoin make(String groupId, {int attempts = 0, String? lastError, bool permanent = false}) => PendingJoin(
        groupId: groupId,
        groupCid: 'bafy$groupId',
        inviteId: 'inv-$groupId',
        inviteNonceB64: base64Encode(List.filled(16, 7)),
        inviterPeerId: 'INVITER',
        addrs: ['/ip4/10.0.0.2/tcp/4001/p2p/INVITER', '/ip4/10.0.0.3/tcp/4001/p2p/OTHER'],
        keyB64: base64Encode(List.generate(32, (i) => i)),
        self: Member(
          peerId: 'ME',
          name: 'Phone Member',
          role: MemberRole.member,
          joinedAt: DateTime.utc(2026, 8, 27, 10),
          publicKey: Uint8List.fromList(List.generate(32, (i) => 255 - i)),
        ),
        createdAt: DateTime.utc(2026, 8, 27, 10, 1),
        attempts: attempts,
        lastError: lastError,
        permanent: permanent,
      );

  test('round-trips through the settings table, including key and public-key bytes', () async {
    final book = PendingJoinBook();
    await book.put(make('g1', attempts: 2, lastError: 'No member online'));
    final back = (await book.all()).single;
    expect(back.groupId, 'g1');
    expect(back.keyBytes, List.generate(32, (i) => i));
    expect(back.self.publicKey, List.generate(32, (i) => 255 - i));
    expect(back.self.name, 'Phone Member');
    expect(back.peerIds, {'INVITER', 'OTHER'});
    expect(back.attempts, 2);
    expect(back.lastError, 'No member online');
    expect(back.permanent, isFalse);
    expect(back.createdAt, DateTime.utc(2026, 8, 27, 10, 1));
  });

  test('put replaces the record for the same group and keeps others in order', () async {
    final book = PendingJoinBook();
    await book.put(make('g1'));
    await book.put(make('g2'));
    await book.put(make('g1', attempts: 5));
    final all = await book.all();
    expect(all.map((p) => p.groupId), ['g2', 'g1']);
    expect(all.last.attempts, 5);
    expect((await book.get('g2'))?.groupId, 'g2');
  });

  test('remove drops the record and the key when the last one goes', () async {
    final book = PendingJoinBook();
    await book.put(make('g1'));
    await book.remove('nope');
    expect(await book.all(), hasLength(1));
    await book.remove('g1');
    expect(await book.all(), isEmpty);
  });

  test('shouldAttempt honours permanent failures and address backoff', () {
    final now = DateTime.utc(2026, 8, 27, 12);
    final j = make('g1');
    expect(j.shouldAttempt(now, {}), isTrue);
    expect(j.shouldAttempt(now, {j.addrs[0]: now.add(const Duration(minutes: 1))}), isTrue,
        reason: 'the other address is still worth a try');
    expect(
      j.shouldAttempt(now, {for (final a in j.addrs) a: now.add(const Duration(minutes: 1))}),
      isFalse,
    );
    expect(
      j.shouldAttempt(now, {for (final a in j.addrs) a: now.subtract(const Duration(seconds: 1))}),
      isTrue,
      reason: 'expired backoff',
    );
    expect(make('g1', permanent: true, lastError: 'Wrong group passphrase').shouldAttempt(now, {}), isFalse);
  });

  test('statusText and wrongPassphrase', () {
    expect(make('g1').statusText, 'Waiting for a member to come online');
    expect(make('g1', attempts: 3).statusText, contains('tried 3×'));
    final wrong = make('g1', permanent: true, lastError: 'Wrong group passphrase');
    expect(wrong.wrongPassphrase, isTrue);
    expect(wrong.statusText, 'Wrong group passphrase');
    final fixed = wrong.copyWith(keyB64: base64Encode(List.filled(32, 1)), clearError: true, permanent: false);
    expect(fixed.permanent, isFalse);
    expect(fixed.lastError, isNull);
  });
}
