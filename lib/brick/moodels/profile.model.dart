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
  final String fullName;
  final String phoneNumber;
  final String? email;
  final bool isAdmin;
  final String avatarUrl;

  Profile({
    String? id,
    String? fullName,
    String? phoneNumber,
    this.email,
    required this.isAdmin,
    String? avatarUrl,
  })  : this.id = id ?? const Uuid().v4(),
        this.fullName = fullName ?? '',
        this.phoneNumber = phoneNumber ?? '',
        this.avatarUrl = avatarUrl ?? '';
}
