import 'dart:typed_data';
import 'package:sqflite_sqlcipher/sqflite.dart';
import '../../models/group_dissolution.dart';
import '../../models/member_removal.dart';
import '../../models/ownership_transfer.dart';
import 'database.dart';

/// Persistence for the group-governance records of DESIGN_PLAN §17/§18 and
/// member removals (§13): `member_removals`, `ownership_transfers`,
/// `group_dissolutions`.
class GovernanceDao {
  // --- member removals -------------------------------------------------------

  Future<void> insertRemoval(MemberRemoval r) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'member_removals',
      {
        'id': r.id,
        'group_id': r.groupId,
        'removed_peer_id': r.removedPeerId,
        'removed_by_peer_id': r.removedByPeerId,
        'reason': r.reason,
        'has_outstanding_loan': r.hasOutstandingLoan ? 1 : 0,
        'outstanding_amount': r.outstandingAmount,
        'action': r.action.name,
        'removed_at': r.removedAt.millisecondsSinceEpoch,
        'admin_signature': r.adminSignature,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<MemberRemoval>> removalsForGroup(String groupId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'member_removals',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'removed_at DESC',
    );
    return rows
        .map((m) => MemberRemoval(
              id: m['id'] as String,
              groupId: m['group_id'] as String,
              removedPeerId: m['removed_peer_id'] as String,
              removedByPeerId: m['removed_by_peer_id'] as String,
              reason: m['reason'] as String,
              hasOutstandingLoan: (m['has_outstanding_loan'] as int? ?? 0) == 1,
              outstandingAmount: (m['outstanding_amount'] as num?)?.toDouble() ?? 0,
              action: RemovalAction.values.firstWhere(
                (a) => a.name == m['action'],
                orElse: () => RemovalAction.remove,
              ),
              removedAt: DateTime.fromMillisecondsSinceEpoch(m['removed_at'] as int, isUtc: true),
              adminSignature: Uint8List.fromList((m['admin_signature'] as List).cast<int>()),
            ))
        .toList();
  }

  // --- ownership transfers ---------------------------------------------------

  Future<void> upsertTransfer(OwnershipTransfer t) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'ownership_transfers',
      {
        'id': t.id,
        'group_id': t.groupId,
        'from_peer_id': t.fromPeerId,
        'to_peer_id': t.toPeerId,
        'transferred_at': t.transferredAt.millisecondsSinceEpoch,
        'old_owner_signature': t.oldOwnerSignature,
        'new_owner_signature': t.newOwnerSignature,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<OwnershipTransfer>> transfersForGroup(String groupId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'ownership_transfers',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'transferred_at DESC',
    );
    return rows
        .map((m) => OwnershipTransfer(
              id: m['id'] as String,
              groupId: m['group_id'] as String,
              fromPeerId: m['from_peer_id'] as String,
              toPeerId: m['to_peer_id'] as String,
              transferredAt: DateTime.fromMillisecondsSinceEpoch(m['transferred_at'] as int, isUtc: true),
              oldOwnerSignature: Uint8List.fromList((m['old_owner_signature'] as List).cast<int>()),
              newOwnerSignature: Uint8List.fromList((m['new_owner_signature'] as List).cast<int>()),
            ))
        .toList();
  }

  // --- dissolutions ----------------------------------------------------------

  Future<void> upsertDissolution(GroupDissolution d) async {
    final db = await AppDatabase.getInstance();
    await db.insert(
      'group_dissolutions',
      {
        'id': d.id,
        'group_id': d.groupId,
        'initiated_by_peer_id': d.initiatedByPeerId,
        'initiated_at': d.initiatedAt.millisecondsSinceEpoch,
        'status': d.status.name,
        'all_loans_settled': d.allLoansSettled ? 1 : 0,
        'funds_distributed': d.fundsDistributed ? 1 : 0,
        'completed_at': d.completedAt?.millisecondsSinceEpoch,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<GroupDissolution?> latestDissolution(String groupId) async {
    final db = await AppDatabase.getInstance();
    final rows = await db.query(
      'group_dissolutions',
      where: 'group_id = ?',
      whereArgs: [groupId],
      orderBy: 'initiated_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final m = rows.first;
    return GroupDissolution(
      id: m['id'] as String,
      groupId: m['group_id'] as String,
      initiatedByPeerId: m['initiated_by_peer_id'] as String,
      initiatedAt: DateTime.fromMillisecondsSinceEpoch(m['initiated_at'] as int, isUtc: true),
      status: DissolutionStatus.values.firstWhere(
        (s) => s.name == m['status'],
        orElse: () => DissolutionStatus.initiating,
      ),
      allLoansSettled: (m['all_loans_settled'] as int? ?? 0) == 1,
      fundsDistributed: (m['funds_distributed'] as int? ?? 0) == 1,
      completedAt: m['completed_at'] != null
          ? DateTime.fromMillisecondsSinceEpoch(m['completed_at'] as int, isUtc: true)
          : null,
    );
  }
}
