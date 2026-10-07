import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/src/app/context.dart';
import 'package:vbank/src/crypto/signing.dart';
import 'package:vbank/src/app/governance_service.dart';
import 'package:vbank/src/app/group_service.dart';
import 'package:vbank/src/app/invite_service.dart';
import 'package:vbank/src/app/key_service.dart';
import 'package:vbank/src/app/loan_service.dart';
import 'package:vbank/src/app/meeting_service.dart';
import 'package:vbank/src/app/report_service.dart';
import 'package:vbank/src/app/transaction_service.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/identity.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/presentation/app_scope.dart';
import 'package:vbank/src/presentation/providers/auth.dart';

import 'fake_repos.dart';

/// Advances frames without waiting for quiescence (spinners never
/// settle). Everything here is in-memory: plain pumps flush all work.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 10; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// A signed-in world with one group (owner plus member, no transactions).
/// The container is for setup only; screens pump their own scope over the
/// same shared fakes.
Future<
  ({
    PresentationWorld world,
    ProviderContainer container,
    Group group,
  })
> setupGroupWorld() async {
  final PresentationWorld world = PresentationWorld();
  final ProviderContainer container = ProviderContainer(
    overrides: [
      appRepositoriesProvider.overrideWithValue(world.repositories),
      appServicesProvider.overrideWithValue(world.services),
    ],
  );
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
  final Group withMember = group.copyWith(
    members: [
      ...group.members,
      Member(
        peerId: 'member',
        name: 'Member',
        joinedAt: world.now,
        publicKey: await world.publicKeyFor('member'),
      ),
    ],
    sequenceNumber: group.sequenceNumber + 1,
  );
  await world.groupRepo.save(withMember);
  return (world: world, container: container, group: withMember);
}

/// A presentation test world: everything in memory, so widget tests run
/// in fake-async time with plain `pump()` — no isolates, no `runAsync`.
final class PresentationWorld {
  /// Fixed test time.
  DateTime now = DateTime.utc(2026, 1, 5, 9);

  /// Id counter.
  int _ids = 0;

  /// Groups and members.
  final MemoryGroupRepository groupRepo = MemoryGroupRepository();

  /// Transactions.
  final MemoryTransactionRepository txRepo = MemoryTransactionRepository();

  /// Loans.
  final MemoryLoanRepository loanRepo = MemoryLoanRepository();

  /// Meetings.
  final MemoryMeetingRepository meetingRepo = MemoryMeetingRepository();

  /// Invites.
  final MemoryInviteRepository inviteRepo = MemoryInviteRepository();

  /// Governance records.
  final MemoryGovernanceRepository govRepo = MemoryGovernanceRepository();

  /// Backups and identity.
  final MemoryBackupRepository backupRepo = MemoryBackupRepository();

  /// Balances.
  final MemoryBalanceRepository balanceRepo = MemoryBalanceRepository();

  /// Settings.
  final MemorySettingsRepository settingsRepo = MemorySettingsRepository();

  /// Repository set for scopes.
  late final AppRepositories repositories = AppRepositories(
    groups: groupRepo,
    transactions: txRepo,
    loans: loanRepo,
    meetings: meetingRepo,
    invites: inviteRepo,
    governance: govRepo,
    backups: backupRepo,
    balances: balanceRepo,
    settings: settingsRepo,
  );

  /// Service set signing as the owner persona.
  late final AppServices services = _services(signAs('owner'));

  /// Signs canonical payloads with a throwaway persona key.
  SignPayload signAs(String peer) => (List<int> payload) async {
        final SimpleKeyPair pair = await _keyFor(peer);
        final Signature signature = await SigningService.sign(payload, pair);
        return Uint8List.fromList(signature.bytes);
      };

  /// Identity keypairs by peer, generated once.
  final Map<String, SimpleKeyPair> _keys = {};

  /// Public key bytes by peer.
  final Map<String, Uint8List> publicKeys = {};

  /// Keypair for [peer], generated once (pure crypto: fake-time safe).
  Future<SimpleKeyPair> _keyFor(String peer) async {
    final SimpleKeyPair? existing = _keys[peer];
    if (existing != null) {
      return existing;
    }
    final SimpleKeyPair pair = await SigningService.generateKeyPair();
    _keys[peer] = pair;
    publicKeys[peer] = Uint8List.fromList(
      await SigningService.extractPublicKeyBytes(pair),
    );
    return pair;
  }

  /// Service set signing as [peer].
  AppServices _services(SignPayload sign) {
    DateTime readClock() => now;
    String nextId() => 'id-${++_ids}';
    final AppClock clock = readClock;
    final IdGenerator ids = nextId;
    final GroupService groups = GroupService(
      groups: groupRepo,
      governance: govRepo,
      loans: loanRepo,
      keys: GroupKeyService(GroupKeyStore(settingsRepo)),
      sign: sign,
      clock: clock,
      ids: ids,
    );
    final TransactionService transactions = TransactionService(
      transactions: txRepo,
      groups: groupRepo,
      balances: balanceRepo,
      sign: sign,
      clock: clock,
      ids: ids,
    );
    return AppServices(
      groups: groups,
      transactions: transactions,
      loans: LoanService(
        loans: loanRepo,
        groups: groups,
        transactions: transactions,
        balances: balanceRepo,
        sign: sign,
        clock: clock,
        ids: ids,
      ),
      meetings: MeetingService(
        meetings: meetingRepo,
        groups: groups,
        clock: clock,
        ids: ids,
      ),
      invites: InviteService(
        invites: inviteRepo,
        sign: sign,
        clock: clock,
        ids: ids,
      ),
      governance: GovernanceService(
        groups: groups,
        transactions: transactions,
        reversals: txRepo,
        governance: govRepo,
        loans: loanRepo,
        balances: balanceRepo,
        sign: sign,
        clock: clock,
        ids: ids,
      ),
      keys: GroupKeyService(GroupKeyStore(settingsRepo)),
      reports: ReportService(
        transactions: txRepo,
        meetings: meetingRepo,
        balances: balanceRepo,
        groups: groupRepo,
      ),
    );
  }

  /// Public key bytes for [peer], generating their keypair on first use.
  Future<Uint8List> publicKeyFor(String peer) async {
    await _keyFor(peer);
    return publicKeys[peer]!;
  }

  /// Signs in as [peer] (default the owner): generates keys, writes the
  /// identity, refreshes auth. Callers pump afterwards to rebuild.
  Future<void> signIn(
    ProviderContainer container, {
    String peer = 'owner',
  }) async {
    await _keyFor(peer);
    await backupRepo.saveIdentity(
      UserIdentity(
        peerId: peer,
        displayName: peer,
        publicKey: publicKeys[peer]!,
        createdAt: now,
      ),
    );
    await container.read(authProvider.notifier).refresh();
  }
}
