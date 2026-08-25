import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/models/group.dart';
import 'package:vbank/models/transaction.dart';

/// Byte fields (signatures, public keys) arrive from IPFS as `List<dynamic>`
/// after `jsonDecode`; the models must not assume `List<int>`.
void main() {
  Map<String, dynamic> roundTrip(Map<String, dynamic> json) =>
      jsonDecode(jsonEncode(json)) as Map<String, dynamic>;

  test('Group with members survives a JSON wire round-trip', () {
    final group = Group(
      id: 'g1',
      name: 'Ngombe Circle',
      config: const GroupConfig(groupId: 'g1', contributionAmount: 20),
      members: [
        Member(
          peerId: 'p1',
          name: 'Arthur',
          role: MemberRole.owner,
          joinedAt: DateTime.utc(2026, 8, 25),
          publicKey: Uint8List.fromList(List.generate(32, (i) => i)),
        ),
      ],
      createdAt: DateTime.utc(2026, 8, 25),
      ownerSignature: Uint8List.fromList(List.generate(64, (i) => 255 - i)),
    );

    final back = Group.fromJson(roundTrip(group.toJson()));
    expect(back.name, 'Ngombe Circle');
    expect(back.config.contributionAmount, 20.0);
    expect(back.members.single.publicKey, group.members.single.publicKey);
    expect(back.members.single.role, MemberRole.owner);
    expect(back.ownerSignature, group.ownerSignature);
  });

  test('Transaction survives a JSON wire round-trip', () {
    final tx = Transaction(
      id: 't1',
      groupId: 'g1',
      fromPeerId: 'p1',
      toPeerId: 'group',
      type: TransactionType.contribution,
      amount: 20,
      timestamp: DateTime.utc(2026, 8, 25, 12),
      sequenceNumber: 1,
      senderSignature: Uint8List.fromList(List.generate(64, (i) => i)),
    );
    final back = Transaction.fromJson(roundTrip(tx.toJson()));
    expect(back.id, 't1');
    expect(back.amount, 20.0);
    expect(back.sequenceNumber, 1);
    expect(back.senderSignature, tx.senderSignature);
    expect(back.type, TransactionType.contribution);
  });
}
