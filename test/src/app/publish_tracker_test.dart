import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/publish_tracker.dart';

import 'harness.dart';

void main() {
  group('PublishTracker', () {
    test('marks and remembers per group', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final PublishTracker tracker = PublishTracker(h.settings);

      expect(await tracker.isPublished('g1', 'tx1'), isFalse);
      await tracker.markPublished('g1', 'tx1');
      expect(await tracker.isPublished('g1', 'tx1'), isTrue);
      expect(await tracker.isPublished('g1', 'tx2'), isFalse);
      expect(await tracker.isPublished('g2', 'tx1'), isFalse);
    });

    test('marking twice stores once', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final PublishTracker tracker = PublishTracker(h.settings);

      await tracker.markPublished('g1', 'tx1');
      await tracker.markPublished('g1', 'tx1');
      final stored = await h.settings.get(PublishTracker.keyFor('g1'));
      final List<dynamic> ids =
          jsonDecode(utf8.decode(stored.value!)) as List<dynamic>;
      expect(ids, ['tx1']);
    });

    test('trims oldest beyond the cap', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final PublishTracker tracker = PublishTracker(h.settings);

      final List<String> seed = [
        for (var i = 0; i < PublishTracker.maxIdsPerGroup; i++) 'id-$i',
      ];
      await h.settings.set(
        PublishTracker.keyFor('g1'),
        Uint8List.fromList(utf8.encode(jsonEncode(seed))),
      );
      await tracker.markPublished('g1', 'id-new');

      expect(await tracker.isPublished('g1', 'id-0'), isFalse);
      expect(await tracker.isPublished('g1', 'id-1'), isTrue);
      expect(await tracker.isPublished('g1', 'id-new'), isTrue);
    });

    test('markAllPublished remembers a batch', () async {
      final AppHarness h = AppHarness();
      await h.init();
      final PublishTracker tracker = PublishTracker(h.settings);

      await tracker.markAllPublished('g1', const ['a', 'b', 'c']);
      expect(await tracker.isPublished('g1', 'a'), isTrue);
      expect(await tracker.isPublished('g1', 'c'), isTrue);
      expect(await tracker.isPublished('g1', 'd'), isFalse);
    });
  });
}
