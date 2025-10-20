import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:uuid/uuid.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'activities'),
)
class Activity extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  @Sqlite(index: true, unique: true)
  final String id;
  @Supabase(name: 'group_id')
  final String groupId;
  @Supabase(name: 'member_id')
  final String? memberId; // Null if a system event
  final String type;
  final String description;
  @Supabase(name: 'created_at')
  final DateTime createdAt;

  Activity({
    String? id,
    required this.groupId,
    this.memberId,
    required this.type,
    required this.description,
    DateTime? createdAt,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now();
}
