import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:uuid/uuid.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'profiles'),
)
class Profile extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  @Sqlite(index: true, unique: true)
  final String id;
  String? fullName;
  String? phoneNumber;
  final bool isAdmin;
  String? avatarUrl;

  Profile({
    String? id,
    String? fullName,
    String? phoneNumber,
    required this.isAdmin,
    String? avatarUrl,
  }) : this.id = id ?? const Uuid().v4();
}
