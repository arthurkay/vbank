// GENERATED CODE DO NOT EDIT
part of '../brick.g.dart';

Future<Profile> _$ProfileFromSupabase(
  Map<String, dynamic> data, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Profile(
    id: data['id'] as String?,
    fullName: data['full_name'] as String?,
    phoneNumber: data['phone_number'] as String?,
    isAdmin: data['is_admin'] as bool,
    avatarUrl: data['avatar_url'] as String?,
  );
}

Future<Map<String, dynamic>> _$ProfileToSupabase(
  Profile instance, {
  required SupabaseProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'full_name': instance.fullName,
    'phone_number': instance.phoneNumber,
    'is_admin': instance.isAdmin,
    'avatar_url': instance.avatarUrl,
  };
}

Future<Profile> _$ProfileFromSqlite(
  Map<String, dynamic> data, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return Profile(
    id: data['id'] as String,
    fullName: data['full_name'] as String,
    phoneNumber: data['phone_number'] as String,
    isAdmin: data['is_admin'] == 1,
    avatarUrl: data['avatar_url'] as String,
  )..primaryKey = data['_brick_id'] as int;
}

Future<Map<String, dynamic>> _$ProfileToSqlite(
  Profile instance, {
  required SqliteProvider provider,
  OfflineFirstWithSupabaseRepository? repository,
}) async {
  return {
    'id': instance.id,
    'full_name': instance.fullName,
    'phone_number': instance.phoneNumber,
    'is_admin': instance.isAdmin ? 1 : 0,
    'avatar_url': instance.avatarUrl,
  };
}

/// Construct a [Profile]
class ProfileAdapter extends OfflineFirstWithSupabaseAdapter<Profile> {
  ProfileAdapter();

  @override
  final supabaseTableName = 'profiles';
  @override
  final defaultToNull = true;
  @override
  final fieldsToSupabaseColumns = {
    'id': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'id',
    ),
    'fullName': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'full_name',
    ),
    'phoneNumber': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'phone_number',
    ),
    'isAdmin': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'is_admin',
    ),
    'avatarUrl': const RuntimeSupabaseColumnDefinition(
      association: false,
      columnName: 'avatar_url',
    ),
  };
  @override
  final ignoreDuplicates = false;
  @override
  final uniqueFields = {'id'};
  @override
  final Map<String, RuntimeSqliteColumnDefinition> fieldsToSqliteColumns = {
    'primaryKey': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: '_brick_id',
      iterable: false,
      type: int,
    ),
    'id': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'id',
      iterable: false,
      type: String,
    ),
    'fullName': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'full_name',
      iterable: false,
      type: String,
    ),
    'phoneNumber': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'phone_number',
      iterable: false,
      type: String,
    ),
    'isAdmin': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'is_admin',
      iterable: false,
      type: bool,
    ),
    'avatarUrl': const RuntimeSqliteColumnDefinition(
      association: false,
      columnName: 'avatar_url',
      iterable: false,
      type: String,
    ),
  };
  @override
  Future<int?> primaryKeyByUniqueColumns(
    Profile instance,
    DatabaseExecutor executor,
  ) async {
    final results = await executor.rawQuery(
      '''
        SELECT * FROM `Profile` WHERE id = ? LIMIT 1''',
      [instance.id],
    );

    // SQFlite returns [{}] when no results are found
    if (results.isEmpty || (results.length == 1 && results.first.isEmpty)) {
      return null;
    }

    return results.first['_brick_id'] as int;
  }

  @override
  final String tableName = 'Profile';

  @override
  Future<Profile> fromSupabase(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProfileFromSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSupabase(
    Profile input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProfileToSupabase(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Profile> fromSqlite(
    Map<String, dynamic> input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProfileFromSqlite(
    input,
    provider: provider,
    repository: repository,
  );
  @override
  Future<Map<String, dynamic>> toSqlite(
    Profile input, {
    required provider,
    covariant OfflineFirstWithSupabaseRepository? repository,
  }) async => await _$ProfileToSqlite(
    input,
    provider: provider,
    repository: repository,
  );
}
