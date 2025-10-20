import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:uuid/uuid.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'contributions'),
)
class Contribution extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  @Sqlite(index: true, unique: true)
  final String id;
  @Supabase(name: 'group_id')
  final String groupId;
  @Supabase(name: 'member_id')
  final String memberId;
  final double amount;
  @Supabase(name: 'transaction_date')
  final DateTime transactionDate;

  Contribution({
    String? id,
    required this.groupId,
    required this.memberId,
    required this.amount,
    DateTime? transactionDate,
  })  : id = id ?? const Uuid().v4(),
        transactionDate = transactionDate ?? DateTime.now();
}
