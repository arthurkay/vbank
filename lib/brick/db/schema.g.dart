// GENERATED CODE DO NOT EDIT
// This file should be version controlled
import 'package:brick_sqlite/db.dart';
part '20251014141738.migration.dart';
part '20251020005337.migration.dart';

/// All intelligently-generated migrations from all `@Migratable` classes on disk
final migrations = <Migration>{
  const Migration20251014141738(),
  const Migration20251020005337(),
};

/// A consumable database structure including the latest generated migration.
final schema = Schema(
  20251020005337,
  generatorVersion: 1,
  tables: <SchemaTable>{
    SchemaTable(
      'Profile',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar, unique: true),
        SchemaColumn('full_name', Column.varchar),
        SchemaColumn('phone_number', Column.varchar),
        SchemaColumn('is_admin', Column.boolean),
        SchemaColumn('avatar_url', Column.varchar),
      },
      indices: <SchemaIndex>{
        SchemaIndex(columns: ['id'], unique: true),
      },
    ),
    SchemaTable(
      'Group',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar, unique: true),
        SchemaColumn('name', Column.varchar),
        SchemaColumn('mission', Column.varchar),
        SchemaColumn('created_at', Column.datetime),
      },
      indices: <SchemaIndex>{
        SchemaIndex(columns: ['id'], unique: true),
      },
    ),
    SchemaTable(
      'GroupMember',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar, unique: true),
        SchemaColumn('group_id', Column.varchar),
        SchemaColumn('member_id', Column.varchar),
        SchemaColumn('role', Column.varchar),
        SchemaColumn('status', Column.varchar),
        SchemaColumn('joined_at', Column.datetime),
      },
      indices: <SchemaIndex>{
        SchemaIndex(columns: ['id'], unique: true),
      },
    ),
    SchemaTable(
      'Loan',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar, unique: true),
        SchemaColumn('group_id', Column.varchar),
        SchemaColumn('member_id', Column.varchar),
        SchemaColumn('principal_amount', Column.Double),
        SchemaColumn('interest_rate', Column.Double),
        SchemaColumn('disbursement_date', Column.datetime),
        SchemaColumn('term_months', Column.integer),
        SchemaColumn('next_repayment_date', Column.datetime),
        SchemaColumn('status', Column.varchar),
        SchemaColumn('current_balance', Column.Double),
      },
      indices: <SchemaIndex>{
        SchemaIndex(columns: ['id'], unique: true),
      },
    ),
    SchemaTable(
      'LoanRepayment',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar, unique: true),
        SchemaColumn('loan_id', Column.varchar),
        SchemaColumn('amount', Column.Double),
        SchemaColumn('payment_date', Column.datetime),
      },
      indices: <SchemaIndex>{
        SchemaIndex(columns: ['id'], unique: true),
      },
    ),
    SchemaTable(
      'Contribution',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar, unique: true),
        SchemaColumn('group_id', Column.varchar),
        SchemaColumn('member_id', Column.varchar),
        SchemaColumn('amount', Column.Double),
        SchemaColumn('transaction_date', Column.datetime),
      },
      indices: <SchemaIndex>{
        SchemaIndex(columns: ['id'], unique: true),
      },
    ),
    SchemaTable(
      'Activity',
      columns: <SchemaColumn>{
        SchemaColumn(
          '_brick_id',
          Column.integer,
          autoincrement: true,
          nullable: false,
          isPrimaryKey: true,
        ),
        SchemaColumn('id', Column.varchar, unique: true),
        SchemaColumn('group_id', Column.varchar),
        SchemaColumn('member_id', Column.varchar),
        SchemaColumn('type', Column.varchar),
        SchemaColumn('description', Column.varchar),
        SchemaColumn('created_at', Column.datetime),
      },
      indices: <SchemaIndex>{
        SchemaIndex(columns: ['id'], unique: true),
      },
    ),
  },
);
