import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/app/key_service.dart';
import 'package:vbank/src/data/repositories/settings_repository.dart';

import '../data/test_db.dart';

void main() {
  group('GroupKeyStore', () {
    Future<GroupKeyStore> openStore() async {
      final Database db = await openTestDb();
      addTearDown(db.close);
      return GroupKeyStore(SqlSettingsRepository(db));
    }

    test('versions accumulate oldest-first', () async {
      final GroupKeyStore store = await openStore();
      final Uint8List v1 = Uint8List.fromList(List.filled(32, 1));
      final Uint8List v2 = Uint8List.fromList(List.filled(32, 2));

      expect((await store.current('g')).value, isNull);
      expect((await store.versions('g')).value, isEmpty);

      expect((await store.setCurrent('g', v1)).isOk, isTrue);
      expect((await store.current('g')).value, v1);
      expect((await store.setVersion('g', 1, v1)).isOk, isTrue);
      expect((await store.setVersion('g', 2, v2)).isOk, isTrue);

      final versions = (await store.versions('g')).value;
      expect(versions.keys.toList(), [1, 2]);
      expect(versions[2], v2);

      expect((await store.delete('g')).isOk, isTrue);
      expect((await store.current('g')).value, isNull);
      expect((await store.versions('g')).value, isEmpty);
    });

    test('allCurrent enumerates groups for backup', () async {
      final GroupKeyStore store = await openStore();
      final Uint8List key = Uint8List.fromList(List.filled(32, 3));

      await store.setCurrent('g-1', key);
      await store.setCurrent('g-2', key);

      final all = (await store.allCurrent()).value;
      expect(all.keys.toSet(), {'g-1', 'g-2'});
    });

    test('closed storage fails writes', () async {
      final Database db = await openTestDb();
      final GroupKeyStore store = GroupKeyStore(SqlSettingsRepository(db));
      await db.close();

      expect(
        (await store.setCurrent('g', Uint8List(0))).failure,
        isNotNull,
      );
      expect(
        (await store.setVersion('g', 1, Uint8List(0))).failure,
        isNotNull,
      );
      expect((await store.versions('g')).value, isEmpty);
      expect((await store.allCurrent()).failure, isNotNull);
    });
  });
}
