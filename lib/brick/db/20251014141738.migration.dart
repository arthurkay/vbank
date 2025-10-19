// GENERATED CODE EDIT WITH CAUTION
// THIS FILE **WILL NOT** BE REGENERATED
// This file should be version controlled and can be manually edited.
part of 'schema.g.dart';

// While migrations are intelligently created, the difference between some commands, such as
// DropTable vs. RenameTable, cannot be determined. For this reason, please review migrations after
// they are created to ensure the correct inference was made.

// The migration version must **always** mirror the file name

const List<MigrationCommand> _migration_20251014141738_up = [
  InsertTable('Profile'),
  InsertTable('Group'),
  InsertColumn('id', Column.varchar, onTable: 'Profile', unique: true),
  InsertColumn('full_name', Column.varchar, onTable: 'Profile'),
  InsertColumn('phone_number', Column.varchar, onTable: 'Profile'),
  InsertColumn('is_admin', Column.boolean, onTable: 'Profile'),
  InsertColumn('avatar_url', Column.varchar, onTable: 'Profile'),
  InsertColumn('id', Column.varchar, onTable: 'Group', unique: true),
  InsertColumn('name', Column.varchar, onTable: 'Group'),
  InsertColumn('mission', Column.varchar, onTable: 'Group'),
  InsertColumn('created_at', Column.datetime, onTable: 'Group'),
  CreateIndex(columns: ['id'], onTable: 'Profile', unique: true),
  CreateIndex(columns: ['id'], onTable: 'Group', unique: true)
];

const List<MigrationCommand> _migration_20251014141738_down = [
  DropTable('Profile'),
  DropTable('Group'),
  DropColumn('id', onTable: 'Profile'),
  DropColumn('full_name', onTable: 'Profile'),
  DropColumn('phone_number', onTable: 'Profile'),
  DropColumn('is_admin', onTable: 'Profile'),
  DropColumn('avatar_url', onTable: 'Profile'),
  DropColumn('id', onTable: 'Group'),
  DropColumn('name', onTable: 'Group'),
  DropColumn('mission', onTable: 'Group'),
  DropColumn('created_at', onTable: 'Group'),
  DropIndex('index_Profile_on_id'),
  DropIndex('index_Group_on_id')
];

//
// DO NOT EDIT BELOW THIS LINE
//

@Migratable(
  version: '20251014141738',
  up: _migration_20251014141738_up,
  down: _migration_20251014141738_down,
)
class Migration20251014141738 extends Migration {
  const Migration20251014141738()
    : super(
        version: 20251014141738,
        up: _migration_20251014141738_up,
        down: _migration_20251014141738_down,
      );
}
