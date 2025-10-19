// GENERATED CODE DO NOT EDIT
// This file should be version controlled
import 'package:brick_sqlite/db.dart';
part '20251014141738.migration.dart';

/// All intelligently-generated migrations from all `@Migratable` classes on disk
final migrations = <Migration>{const Migration20251014141738()};

/// A consumable database structure including the latest generated migration.
final schema = Schema(
  20251014141738,
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
  },
);
