import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vbank/core/crypto/identity.dart';
import 'package:vbank/core/storage/settings_dao.dart';
import 'package:vbank/core/storage/user_identity_dao.dart';
import 'package:vbank/models/group.dart';
import 'package:vbank/models/transaction.dart';
import 'package:vbank/services/backup_service.dart';
import 'package:vbank/services/cloud_backup_service.dart';
import 'package:vbank/services/group_key_service.dart';
import 'package:vbank/services/group_service.dart';
import 'package:vbank/services/invite_service.dart';
import 'package:vbank/services/loan_service.dart';
import 'package:vbank/services/transaction_service.dart';

import 'helpers/test_db.dart';

/// A cloud store that lives in a map: what the service does around it is what
/// we test (scheduling, retention, encryption, restore round trip).
class FakeStore implements CloudBackupStore {
  final files = <String, Uint8List>{};
  final stamps = <String, DateTime>{};
  bool signedIn = true;
  int uploads = 0;
  DateTime clock = DateTime.utc(2026, 9, 3, 2);

  @override
  String get name => 'Fake Cloud';
  @override
  Future<bool> signIn({required bool interactive}) async => signedIn;
  @override
  Future<List<CloudBackupFile>> list() async => [
        for (final e in files.entries) CloudBackupFile(id: e.key, name: e.key, size: e.value.length, modified: stamps[e.key]!),
      ];
  @override
  Future<CloudBackupFile> upload(String name, Uint8List bytes) async {
    uploads++;
    files[name] = bytes;
    stamps[name] = clock = clock.add(const Duration(minutes: 1));
    return CloudBackupFile(id: name, name: name, size: bytes.length, modified: stamps[name]!);
  }
  @override
  Future<Uint8List> download(CloudBackupFile file) async => files[file.id]!;
  @override
  Future<void> delete(CloudBackupFile file) async {
    files.remove(file.id);
    stamps.remove(file.id);
  }
}

void main() {
  setUp(useInMemoryDatabase);
  tearDown(closeTestDatabase);

  late FakeStore store;
  late MemoryVault vault;
  var now = DateTime.utc(2026, 9, 3, 2);
  var wifi = true;
  late CloudBackupService cloud;

  Future<void> seedAccountAndGroup() async {
    final owner = await IdentityManager.createIdentity('Owner');
    final groups = GroupService(groupKeyService: GroupKeyService(), inviteService: InviteService());
    final txs = TransactionService();
    final identityDao = await importIdentity(owner);
    final circle = await groups.createGroup(
      name: 'Backup Circle',
      config: const GroupConfig(groupId: '', contributionAmount: 20),
      passphrase: 'backup-circle-2026',
      ownerPeerId: owner.identity.peerId,
      ownerName: 'Owner',
      ownerPublicKey: owner.identity.publicKey,
      ownerKeyPair: owner.keyPair,
    );
    await txs.createTransaction(
      groupId: circle.id,
      authorPeerId: owner.identity.peerId,
      authorKeyPair: owner.keyPair,
      fromPeerId: owner.identity.peerId,
      toPeerId: 'group',
      type: TransactionType.contribution,
      amount: 20,
    );
    expect(identityDao, isNotNull);
    // Touch LoanService so the loans table exists on this schema too.
    LoanService(groupService: groups, transactionService: txs);
  }

  setUp(() {
    store = FakeStore();
    vault = MemoryVault();
    now = DateTime.utc(2026, 9, 3, 2);
    wifi = true;
    cloud = CloudBackupService(store: store, vault: vault, onWifi: () async => wifi, now: () => now);
  });

  test('disabled by default; enable needs a valid passphrase and a signed-in store', () async {
    expect(await cloud.enabled(), isFalse);
    expect(await cloud.isDue(), isFalse);
    expect(() => cloud.enable(passphrase: 'short'), throwsArgumentError);
    store.signedIn = false;
    expect(() => cloud.enable(passphrase: 'a-good-passphrase'), throwsStateError);
    store.signedIn = true;
    await cloud.enable(passphrase: 'a-good-passphrase');
    expect(await cloud.enabled(), isTrue);
    expect(await cloud.hasPassphrase(), isTrue);
    expect(await cloud.isDue(), isTrue, reason: 'never backed up');
  });

  test('runIfDue backs up once per interval, honours Wi-Fi only, keeps the newest three', () async {
    await seedAccountAndGroup();
    await cloud.enable(passphrase: 'a-good-passphrase');

    wifi = false;
    expect(await cloud.runIfDue(), isFalse, reason: 'Wi-Fi only and on mobile data');
    wifi = true;
    expect(await cloud.runIfDue(), isTrue);
    expect(store.uploads, 1);
    expect(await cloud.lastBackupAt(), now.toUtc());
    expect((await cloud.lastBackupSize())!, greaterThan(100));

    expect(await cloud.runIfDue(), isFalse, reason: 'not due yet');
    now = now.add(const Duration(hours: 23));
    expect(await cloud.runIfDue(), isFalse);
    now = now.add(const Duration(hours: 2));
    expect(await cloud.runIfDue(), isTrue);
    expect(store.uploads, 2);

    await cloud.setIntervalDays(7);
    now = now.add(const Duration(days: 2));
    expect(await cloud.runIfDue(), isFalse, reason: 'weekly now');
    now = now.add(const Duration(days: 6));
    expect(await cloud.runIfDue(), isTrue);
    now = now.add(const Duration(days: 8));
    expect(await cloud.runIfDue(), isTrue);
    expect(store.uploads, 4);
    expect(store.files.length, CloudBackupService.keep, reason: 'old copies pruned');

    // The uploaded file is a sealed envelope that decrypts with the passphrase
    // and carries the records (payload v3).
    final newest = (await cloud.listRemote()).first;
    final bytes = await cloud.download(newest);
    expect(BackupEnvelope.tryDecode(bytes), isNotNull);
    final restored = await BackupService().decryptBackup(encryptedPayload: bytes, passphrase: 'a-good-passphrase');
    expect(restored, isNotNull);
    expect(restored!.groups.map((g) => g.name), ['Backup Circle']);
    expect(restored.transactions, hasLength(1));
    expect(restored.groupKeys, hasLength(1));
    expect(await BackupService().decryptBackup(encryptedPayload: bytes, passphrase: 'wrong-passphrase'), isNull);
  });

  test('failures are recorded, not thrown; disable forgets the passphrase', () async {
    await seedAccountAndGroup();
    await cloud.enable(passphrase: 'a-good-passphrase');
    store.signedIn = false;
    expect(await cloud.runIfDue(), isFalse);
    expect(await cloud.lastError(), contains('Not signed in'));
    store.signedIn = true;
    expect(await cloud.runIfDue(), isTrue);
    expect(await cloud.lastError(), isNull);
    await cloud.disable();
    expect(await cloud.enabled(), isFalse);
    expect(await cloud.hasPassphrase(), isFalse);
    expect(await SettingsDao().getBool(SettingKeys.cloudBackupEnabled, defaultValue: true), isFalse);
  });
}

/// Stores the generated identity the way the app does on account creation.
Future<Object?> importIdentity(GeneratedIdentity g) async {
  final dao = UserIdentityDao();
  await dao.insert(UserIdentityData(
    peerId: g.identity.peerId,
    displayName: g.identity.displayName,
    publicKey: g.identity.publicKey,
    privateKey: g.privateKeySeed,
    createdAt: g.identity.createdAt,
  ));
  return dao;
}
