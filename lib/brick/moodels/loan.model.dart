import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
import 'package:brick_sqlite/brick_sqlite.dart';
import 'package:brick_supabase/brick_supabase.dart';
import 'package:uuid/uuid.dart';

@ConnectOfflineFirstWithSupabase(
  supabaseConfig: SupabaseSerializable(tableName: 'loans'),
)
class Loan extends OfflineFirstWithSupabaseModel {
  @Supabase(unique: true)
  @Sqlite(index: true, unique: true)
  final String id;
  @Supabase(name: 'group_id')
  final String groupId;
  @Supabase(name: 'member_id')
  final String memberId;
  @Supabase(name: 'principal_amount')
  final double principalAmount;
  @Supabase(name: 'interest_rate')
  final double interestRate;
  @Supabase(name: 'disbursement_date')
  final DateTime disbursementDate;
  @Supabase(name: 'term_months')
  final int termMonths;
  @Supabase(name: 'next_repayment_date')
  final DateTime? nextRepaymentDate;
  final String status;
  @Supabase(name: 'current_balance')
  final double currentBalance;

  Loan({
    String? id,
    required this.groupId,
    required this.memberId,
    required this.principalAmount,
    required this.interestRate,
    required this.disbursementDate,
    required this.termMonths,
    this.nextRepaymentDate,
    this.status = 'Active',
    required this.currentBalance,
  }) : this.id = id ?? const Uuid().v4();
}
