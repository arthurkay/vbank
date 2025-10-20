import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:uuid/uuid.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'group_members'),
)
class GroupMember extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  @Sqlite(index: true, unique: true)
  final String id;
  @Supabase(name: 'group_id')
  final String groupId;
  @Supabase(name: 'member_id')
  final String memberId;
  final String role;
  final String status;
  @Supabase(name: 'joined_at')
  final DateTime joinedAt;

  GroupMember({
    String? id,
    required this.groupId,
    required this.memberId,
    this.role = 'Member',
    this.status = 'Active',
    DateTime? joinedAt,
  })  : id = id ?? const Uuid().v4(),
        joinedAt = joinedAt ?? DateTime.now();
}
