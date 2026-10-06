import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/transaction_service.dart';
import 'package:vbank/src/domain/core/failure.dart';
import 'package:vbank/src/domain/transactions.dart';

import 'harness.dart';

void main() {
  late AppHarness world;
  setUp(() async {
    world = AppHarness();
    await world.init();
  });

  group('TransactionService', () {
    test('records signed contributions and moves balances', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');

      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 250,
        note: 'weekly',
      ))
          .value;

      expect(tx.sequenceNumber, 2, reason: 'two seed contributions first');
      expect(tx.authorPeerId, 'owner');
      expect(tx.senderSignature, isNotEmpty);

      // Signature verifies against the roster key.
      expect(
        await owner.transactions.verifySignature(
          tx,
          world.publicKeys['owner']!,
        ),
        isTrue,
      );

      final balances = await owner.transactions.balances.listByGroup(gid);
      final member = balances.value.firstWhere((b) => b.peerId == 'member');
      expect(member.totalContributed, 350);
      expect(member.netBalance, 350);
    });

    test('sequences allocate in order without gaps', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');

      for (var i = 0; i < 3; i++) {
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'member',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 10,
        );
      }
      final seqs = (await owner.transactions.listByGroup(gid)).value.map(
        (Transaction t) => t.sequenceNumber,
      );
      expect(seqs.toList(), [0, 1, 2, 3, 4]);
    });

    test('members cannot record, strangers cannot, dissolved cannot', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final ServiceStack member = world.stackFor('member');

      Future<Failure> attempt(ServiceStack stack, String peer) async {
        final result = await stack.transactions.createTransaction(
          groupId: gid,
          authorPeerId: peer,
          fromPeerId: peer,
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 10,
        );
        return result.failure;
      }

      expect(await attempt(member, 'member'), isA<PermissionFailure>());
      expect(
        await attempt(world.stackFor('stranger'), 'stranger'),
        isA<PermissionFailure>(),
      );
      expect(
        await owner.transactions.createTransaction(
          groupId: 'nope',
          authorPeerId: 'owner',
          fromPeerId: 'owner',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 10,
        ).then((r) => r.failure),
        isA<NotFoundFailure>(),
      );
      expect(
        await owner.transactions.createTransaction(
          groupId: gid,
          authorPeerId: 'owner',
          fromPeerId: 'owner',
          toPeerId: 'group',
          type: TransactionType.contribution,
          amount: 0,
        ).then((r) => r.failure),
        isA<ValidationFailure>(),
      );
    });

    test('remote imports verify, dedupe and reverse atomically', () async {
      final String gid = await world.seedGroup();
      final ServiceStack owner = world.stackFor('owner');
      final Transaction tx = (await owner.transactions.createTransaction(
        groupId: gid,
        authorPeerId: 'owner',
        fromPeerId: 'member',
        toPeerId: 'group',
        type: TransactionType.contribution,
        amount: 100,
      ))
          .value;

      // Same record from a peer: verified, recognised as duplicate.
      expect(
        (await owner.transactions.importRemote(
          tx,
          authorPublicKey: world.publicKeys['owner']!,
        ))
            .value,
        ImportResult.duplicate,
      );

      // Forged signature: rejected, nothing written.
      final Transaction forged = tx.copyWith(note: 'forged amount stays');
      expect(
        (await owner.transactions.importRemote(
          forged,
          authorPublicKey: world.publicKeys['owner']!,
        )).failure,
        isA<IntegrityFailure>(),
      );

      // Reversal undoes the exact balance effect.
      final before = await owner.transactions.balances.listByGroup(gid);
      final double netBefore = before.value
          .firstWhere((b) => b.peerId == 'member')
          .netBalance;
      expect(
        (await owner.transactions.markReversed(tx.id)).isOk,
        isTrue,
      );
      expect(
        (await owner.transactions.markReversed(tx.id)).isOk,
        isTrue,
        reason: 'idempotent',
      );
      final after = await owner.transactions.balances.listByGroup(gid);
      expect(
        after.value.firstWhere((b) => b.peerId == 'member').netBalance,
        netBefore - 100,
      );
      expect(
        (await owner.transactions.getById(tx.id)).value.status,
        TransactionStatus.reversed,
      );
    });
  });
}
