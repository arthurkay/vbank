import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:vbank/src/app/context.dart';
import 'package:vbank/src/app/governance_service.dart';
import 'package:vbank/src/app/group_service.dart';
import 'package:vbank/src/app/invite_service.dart';
import 'package:vbank/src/app/key_service.dart';
import 'package:vbank/src/app/loan_service.dart';
import 'package:vbank/src/app/meeting_service.dart';
import 'package:vbank/src/app/report_service.dart';
import 'package:vbank/src/app/transaction_service.dart';
import 'package:vbank/src/crypto/signing.dart';
import 'package:vbank/src/data/repositories/backup_repository.dart';
import 'package:vbank/src/data/repositories/balance_repository.dart';
import 'package:vbank/src/data/repositories/governance_repository.dart';
import 'package:vbank/src/data/repositories/group_repository.dart';
import 'package:vbank/src/data/repositories/invite_repository.dart';
import 'package:vbank/src/data/repositories/loan_repository.dart';
import 'package:vbank/src/data/repositories/meeting_repository.dart';
import 'package:vbank/src/data/repositories/settings_repository.dart';
import 'package:vbank/src/data/repositories/transaction_repository.dart';
import 'package:vbank/src/domain/group.dart';
import 'package:vbank/src/domain/meeting_time.dart';
import 'package:vbank/src/domain/membership.dart';
import 'package:vbank/src/domain/transactions.dart';

import '../data/test_db.dart';

/// One persona's service stack. Every device runs its own stack; tests
/// share repositories to simulate converged state, with a signer per
/// persona.
final class ServiceStack {
  /// Roster and governance records.
  final GroupService groups;

  /// Money movements.
  final TransactionService transactions;

  /// Loan lifecycle.
  final LoanService loans;

  /// Meetings.
  final MeetingService meetings;

  /// Invites.
  final InviteService invites;

  /// Corrections and dissolution.
  final GovernanceService governance;

  /// Creates a stack.
  const ServiceStack({
    required this.groups,
    required this.transactions,
    required this.loans,
    required this.meetings,
    required this.invites,
    required this.governance,
  });
}

/// A whole test world: one database, all repositories, one stack per
/// persona, a pinnable clock and counting ids.
final class AppHarness {
  /// Pinned time; advance with [elapse].
  DateTime now = DateTime.utc(2026, 1, 5, 9);

  /// Id counter.
  int _ids = 0;

  /// Identity keypairs by peer id.
  final Map<String, SimpleKeyPair> _keys = {};

  /// Public key bytes by peer id.
  final Map<String, Uint8List> publicKeys = {};

  /// Group keys.
  late final GroupKeyService keys;

  /// Statements.
  late final ReportService reports;

  late final SqlGroupRepository _groupRepo;
  late final SqlTransactionRepository _txRepo;
  late final SqlLoanRepository _loanRepo;
  late final SqlMeetingRepository _meetingRepo;
  late final SqlInviteRepository _inviteRepo;
  late final SqlGovernanceRepository _govRepo;
  late final SqlBackupRepository _backupRepo;
  late final SqlBalanceRepository _balanceRepo;
  late final SqlSettingsRepository _settingsRepo;

  /// Opens the world. Call in `setUp`, or once per file with fresh state
  /// per test via [reset].
  Future<void> init() async {
    final Database db = await openTestDb();
    _groupRepo = SqlGroupRepository(db);
    _txRepo = SqlTransactionRepository(db);
    _loanRepo = SqlLoanRepository(db);
    _meetingRepo = SqlMeetingRepository(db);
    _inviteRepo = SqlInviteRepository(db);
    _govRepo = SqlGovernanceRepository(db);
    _backupRepo = SqlBackupRepository(db);
    _balanceRepo = SqlBalanceRepository(db);
    _settingsRepo = SqlSettingsRepository(db);
    keys = GroupKeyService(GroupKeyStore(_settingsRepo));
    reports = ReportService(
      transactions: _txRepo,
      meetings: _meetingRepo,
      balances: _balanceRepo,
      groups: _groupRepo,
    );
    addTearDown(() async {
      await _groupRepo.close();
      await _txRepo.close();
      await _loanRepo.close();
      await _meetingRepo.close();
      await _inviteRepo.close();
      await _govRepo.close();
      await _backupRepo.close();
      await _balanceRepo.close();
      await _settingsRepo.close();
    });
  }

  /// Moves the clock forward.
  void elapse(Duration d) {
    now = now.add(d);
  }

  /// The signer for [peer], generating their keypair on first use.
  SignPayload signerFor(String peer) => (List<int> payload) async {
        final SimpleKeyPair kp = await keyFor(peer);
        final Signature sig = await SigningService.sign(payload, kp);
        return Uint8List.fromList(sig.bytes);
      };

  /// Identity keypair for [peer], generated once.
  Future<SimpleKeyPair> keyFor(String peer) async {
    final SimpleKeyPair? existing = _keys[peer];
    if (existing != null) {
      return existing;
    }
    final SimpleKeyPair kp = await SigningService.generateKeyPair();
    _keys[peer] = kp;
    publicKeys[peer] = Uint8List.fromList(
      await SigningService.extractPublicKeyBytes(kp),
    );
    return kp;
  }

  /// A persona's stack: every call signs as [peer].
  ServiceStack stackFor(String peer) {
    final SignPayload sign = signerFor(peer);
    DateTime readClock() => now;
    String nextId() => 'id-${++_ids}';
    final AppClock clock = readClock;
    final IdGenerator ids = nextId;
    final GroupService groupService = GroupService(
      groups: _groupRepo,
      governance: _govRepo,
      loans: _loanRepo,
      keys: keys,
      sign: sign,
      clock: clock,
      ids: ids,
    );
    final TransactionService txService = TransactionService(
      transactions: _txRepo,
      groups: _groupRepo,
      balances: _balanceRepo,
      sign: sign,
      clock: clock,
      ids: ids,
    );
    final LoanService loanService = LoanService(
      loans: _loanRepo,
      groups: groupService,
      transactions: txService,
      balances: _balanceRepo,
      sign: sign,
      clock: clock,
      ids: ids,
    );
    final MeetingService meetingService = MeetingService(
      meetings: _meetingRepo,
      groups: groupService,
      clock: clock,
      ids: ids,
    );
    final InviteService inviteService = InviteService(
      invites: _inviteRepo,
      sign: sign,
      clock: clock,
      ids: ids,
    );
    final GovernanceService governanceService = GovernanceService(
      groups: groupService,
      transactions: txService,
      reversals: _txRepo,
      governance: _govRepo,
      loans: _loanRepo,
      balances: _balanceRepo,
      sign: sign,
      clock: clock,
      ids: ids,
    );
    return ServiceStack(
      groups: groupService,
      transactions: txService,
      loans: loanService,
      meetings: meetingService,
      invites: inviteService,
      governance: governanceService,
    );
  }

  /// Creates a group owned by [owner] with one funded member [member]:
  /// owner creates, member joins the roster, both contribute. Returns the
  /// group id. Groups are created with a random key (invite flow).
  Future<String> seedGroup({
    String owner = 'owner',
    String ownerName = 'Owner',
    String member = 'member',
    String memberName = 'Member',
    double contribution = 100,
  }) async {
    await keyFor(owner);
    await keyFor(member);
    final ServiceStack ownerStack = stackFor(owner);
    final Group group = (await ownerStack.groups.createGroup(
      name: 'Test Group',
      config: const GroupConfig(
        groupId: 'template',
        contributionAmount: 100,
        meetingTime: MeetingTime(hour: 9, minute: 0),
      ),
      ownerPeerId: owner,
      ownerName: ownerName,
      ownerPublicKey: publicKeys[owner]!,
    ))
        .value;
    final Group withMember = group.copyWith(
      members: [
        ...group.members,
        Member(
          peerId: member,
          name: memberName,
          joinedAt: now,
          publicKey: publicKeys[member]!,
        ),
      ],
      sequenceNumber: group.sequenceNumber + 1,
    );
    await ownerStack.groups.saveGroup(withMember);
    for (final String who in [owner, member]) {
      final result = await stackFor(who).transactions.createTransaction(
            groupId: group.id,
            authorPeerId: owner,
            fromPeerId: who,
            toPeerId: 'group',
            type: TransactionType.contribution,
            amount: contribution,
          );
      assert(result.isOk, 'seed contribution failed: ${result.failure}');
    }
    return group.id;
  }
}
