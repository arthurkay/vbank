import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:uuid/uuid.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'loan_repayments'),
)
class LoanRepayment extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  @Sqlite(index: true, unique: true)
  final String id;
  @Supabase(name: 'loan_id')
  final String loanId;
  final double amount;
  @Supabase(name: 'payment_date')
  final DateTime paymentDate;

  LoanRepayment({
    String? id,
    required this.loanId,
    required this.amount,
    DateTime? paymentDate,
  })  : id = id ?? const Uuid().v4(),
        paymentDate = paymentDate ?? DateTime.now();
}
