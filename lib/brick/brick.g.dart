// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_core/query.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_sqlite/db.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_offline_first_with_supabase/brick_offline_first_with_supabase.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_sqlite/brick_sqlite.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:brick_supabase/brick_supabase.dart';
// ignore: unused_import, unused_shown_name, unnecessary_import
import 'package:uuid/uuid.dart';// GENERATED CODE DO NOT EDIT
// ignore: unused_import
import 'dart:convert';
import 'package:brick_sqlite/brick_sqlite.dart' show SqliteModel, SqliteAdapter, SqliteModelDictionary, RuntimeSqliteColumnDefinition, SqliteProvider;
import 'package:brick_supabase/brick_supabase.dart' show SupabaseProvider, SupabaseModel, SupabaseAdapter, SupabaseModelDictionary;
// ignore: unused_import, unused_shown_name
import 'package:brick_offline_first/brick_offline_first.dart' show RuntimeOfflineFirstDefinition;
// ignore: unused_import, unused_shown_name
import 'package:sqflite_common/sqlite_api.dart' show DatabaseExecutor;

import '../brick/moodels/profile.model.dart';
import '../brick/moodels/group.model.dart';
import '../brick/moodels/group_member.model.dart';
import '../brick/moodels/loan.model.dart';
import '../brick/moodels/loan_repayment.model.dart';
import '../brick/moodels/contribution.model.dart';
import '../brick/moodels/activity.model.dart';

part 'adapters/profile_adapter.g.dart';
part 'adapters/group_adapter.g.dart';
part 'adapters/group_member_adapter.g.dart';
part 'adapters/loan_adapter.g.dart';
part 'adapters/loan_repayment_adapter.g.dart';
part 'adapters/contribution_adapter.g.dart';
part 'adapters/activity_adapter.g.dart';

/// Supabase mappings should only be used when initializing a [SupabaseProvider]
final Map<Type, SupabaseAdapter<SupabaseModel>> supabaseMappings = {
  Profile: ProfileAdapter(),
  Group: GroupAdapter(),
  GroupMember: GroupMemberAdapter(),
  Loan: LoanAdapter(),
  LoanRepayment: LoanRepaymentAdapter(),
  Contribution: ContributionAdapter(),
  Activity: ActivityAdapter()
};
final supabaseModelDictionary = SupabaseModelDictionary(supabaseMappings);

/// Sqlite mappings should only be used when initializing a [SqliteProvider]
final Map<Type, SqliteAdapter<SqliteModel>> sqliteMappings = {
  Profile: ProfileAdapter(),
  Group: GroupAdapter(),
  GroupMember: GroupMemberAdapter(),
  Loan: LoanAdapter(),
  LoanRepayment: LoanRepaymentAdapter(),
  Contribution: ContributionAdapter(),
  Activity: ActivityAdapter()
};
final sqliteModelDictionary = SqliteModelDictionary(sqliteMappings);
