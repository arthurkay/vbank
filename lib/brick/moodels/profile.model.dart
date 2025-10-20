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
  @Supabase(name: 'full_name')
  final String? fullName;
  @Supabase(name: 'phone_number')
  final String? phoneNumber;
  final bool isAdmin;
  String? avatarUrl;

  Profile({
    String? id,
    required this.fullName,
    required this.phoneNumber,
    required this.isAdmin,
    this.avatarUrl,
  }) : id = id ?? const Uuid().v4();
}
