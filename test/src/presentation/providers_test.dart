import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/providers/auth.dart';
import 'package:vbank/src/presentation/providers/groups.dart';

import 'pump.dart';

void main() {
  group('providers', () {
    test('auth reflects the identity row', () async {
      final PresentationWorld world = PresentationWorld();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appRepositoriesProvider.overrideWithValue(world.repositories),
          appServicesProvider.overrideWithValue(world.services),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(authProvider).isLoading, isTrue);
      await container.read(authProvider.notifier).refresh();
      expect(container.read(authProvider).isSignedIn, isFalse);

      await world.signIn(container);
      expect(container.read(authProvider).isSignedIn, isTrue);
      expect(container.read(authProvider).identity?.peerId, 'owner');
    });

    test('selection follows the open group', () async {
      final PresentationWorld world = PresentationWorld();
      final ProviderContainer container = ProviderContainer(
        overrides: [
          appRepositoriesProvider.overrideWithValue(world.repositories),
          appServicesProvider.overrideWithValue(world.services),
        ],
      );
      addTearDown(container.dispose);
      await world.signIn(container);
      final Group group = (await world.services.groups.createGroup(
        name: 'Test Group',
        config: const GroupConfig(
          groupId: 'template',
          contributionAmount: 100,
          meetingTime: MeetingTime(hour: 9, minute: 0),
        ),
        ownerPeerId: 'owner',
        ownerName: 'Owner',
        ownerPublicKey: world.publicKeys['owner']!,
      ))
          .value;

      expect(
        await container.read(selectedGroupProvider.future),
        isNull,
      );
      container.read(selectedGroupIdProvider.notifier).state = group.id;
      expect(
        (await container.read(selectedGroupProvider.future))?.id,
        group.id,
      );
      expect(
        await container.read(groupListProvider.future),
        hasLength(1),
      );
    });
  });
}
